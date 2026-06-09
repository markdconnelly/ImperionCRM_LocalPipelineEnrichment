function Invoke-ImperionVectorizeKnowledge {
    <#
    .SYNOPSIS
        Embed gold knowledge objects into `knowledge_embedding` (chunk → Voyage → pgvector).
    .DESCRIPTION
        THE vectorization stage (CLAUDE.md §7, ADR-0009; build-order task 8). This node owns
        ALL embedding generation system-wide (front-end ADR-0041 / migration 0045): the
        backend agent only ever embeds queries.

        For every `knowledge_object` (optionally filtered by entity type), the body is
        chunked under the pinned chunking policy and each chunk's content hash is compared
        with what is already embedded for the pinned (model, chunking_version). Objects
        whose chunk-hash sets match are SKIPPED — unchanged text is never re-embedded, so
        re-runs converge and never re-bill. Stale objects are embedded through Voyage
        (`voyage-3-large` @ 1024, input_type=document) and their chunk rows replaced
        atomically per object (delete the object's rows for this model+version, insert the
        new set) — a different model/chunking version's rows are never touched, which is
        what makes versioned re-embeds safe (docs/database/vector-lifecycle.md).

        Emits the required cost telemetry on every run: objects scanned/unchanged/embedded,
        chunks, billed tokens, estimated USD, duration.
    .PARAMETER EntityType
        Restrict to one entity type (e.g. 'account'). Default: all knowledge objects.
    .PARAMETER TenantId
        Restrict to one tenant's knowledge. Default: all tenants this node owns.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. When omitted, one is opened from config
        (ADR-0003 short-lived token) and disposed.
    .OUTPUTS
        The run tally { objects; unchanged; embedded; chunks; tokens; estimatedUsd }.
    .EXAMPLE
        Invoke-ImperionVectorizeKnowledge
    .EXAMPLE
        Invoke-ImperionVectorizeKnowledge -EntityType account -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string] $EntityType,
        [string] $TenantId,
        $Connection
    )

    $contract = Get-ImperionVectorContract
    $runStart = Get-Date

    $ownsConnection = $false
    $conn = $Connection
    if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $objects = Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT ko.id::text AS id, ko.entity_type, ko.title, ko.body
  FROM knowledge_object ko
 WHERE (@type::text IS NULL OR ko.entity_type = @type)
   AND (@tenant::text IS NULL OR ko.tenant_id = @tenant)
 ORDER BY ko.entity_type, ko.id
'@ -Parameters @{ type = $(if ($EntityType) { $EntityType } else { $null }); tenant = $(if ($TenantId) { $TenantId } else { $null }) }

        if (-not $objects) {
            Write-ImperionLog -Source 'vector' -Message 'vectorize: no knowledge objects found (run the knowledge sync first).'
            return [pscustomobject]@{ objects = 0; unchanged = 0; embedded = 0; chunks = 0; tokens = 0; estimatedUsd = 0 }
        }

        # Existing chunk hashes for the PINNED (model, chunking_version) only — other
        # versions coexist untouched (versioned re-embed lifecycle).
        $existingChunksByObject = @{}
        Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT ke.knowledge_object_id::text AS id, ke.chunk_index, ke.content_hash
  FROM knowledge_embedding ke
 WHERE ke.embedding_model = @model AND ke.chunking_version = @version
 ORDER BY ke.knowledge_object_id, ke.chunk_index
'@ -Parameters @{ model = $contract.EmbeddingModel; version = $contract.ChunkingVersion } | ForEach-Object {
            if (-not $existingChunksByObject.ContainsKey($_.id)) {
                $existingChunksByObject[$_.id] = [System.Collections.Generic.List[string]]::new()
            }
            $existingChunksByObject[$_.id].Add($_.content_hash)
        }

        # Chunk every object locally (cheap CPU) and keep only the stale ones.
        $staleObjects = [System.Collections.Generic.List[object]]::new()
        $unchanged = 0
        foreach ($object in $objects) {
            $chunks = @(Split-ImperionTextChunk -Text $object.body)
            if ($chunks.Count -eq 0) { $unchanged++; continue }
            $chunkHashes = @($chunks | ForEach-Object { Get-ImperionContentHash -InputObject @{ chunk_text = $_ } })
            $existing = if ($existingChunksByObject.ContainsKey($object.id)) { @($existingChunksByObject[$object.id]) } else { @() }
            if (($existing -join '|') -eq ($chunkHashes -join '|')) { $unchanged++; continue }
            $staleObjects.Add([pscustomobject]@{
                Id = $object.id; EntityType = $object.entity_type; Title = $object.title
                Chunks = $chunks; ChunkHashes = $chunkHashes
            })
        }

        if ($staleObjects.Count -eq 0) {
            Write-ImperionLog -Level Metric -Source 'vector' -Message 'vectorize: everything already embedded; nothing to do.' -Data @{
                objects = @($objects).Count; unchanged = $unchanged; embedded = 0; chunks = 0; tokens = 0
            }
            return [pscustomobject]@{ objects = @($objects).Count; unchanged = $unchanged; embedded = 0; chunks = 0; tokens = 0; estimatedUsd = 0 }
        }

        $totalChunks = ($staleObjects | ForEach-Object { $_.Chunks.Count } | Measure-Object -Sum).Sum
        if (-not $PSCmdlet.ShouldProcess("$($staleObjects.Count) knowledge objects ($totalChunks chunks) via Voyage $($contract.EmbeddingModel)", 'embed + upsert vectors')) {
            return [pscustomobject]@{ objects = @($objects).Count; unchanged = $unchanged; embedded = 0; chunks = $totalChunks; tokens = 0; estimatedUsd = 0 }
        }

        # One flattened embedding pass (the connect layer batches to the API limit) —
        # then write back per object so a mid-run failure leaves prior objects complete.
        $allChunkTexts = @($staleObjects | ForEach-Object { $_.Chunks })
        $embeddingResult = Get-ImperionVoyageEmbedding -Text $allChunkTexts -InputType document

        $cursor = 0
        foreach ($stale in $staleObjects) {
            Invoke-ImperionDbNonQuery -Connection $conn -Sql @'
DELETE FROM knowledge_embedding
 WHERE knowledge_object_id = @id::uuid
   AND embedding_model = @model AND chunking_version = @version
'@ -Parameters @{ id = $stale.Id; model = $contract.EmbeddingModel; version = $contract.ChunkingVersion } | Out-Null

            for ($chunkIndex = 0; $chunkIndex -lt $stale.Chunks.Count; $chunkIndex++) {
                $vector = $embeddingResult.Embeddings[$cursor]
                $cursor++
                $vectorLiteral = '[' + (($vector | ForEach-Object { $_.ToString([System.Globalization.CultureInfo]::InvariantCulture) }) -join ',') + ']'
                Invoke-ImperionDbNonQuery -Connection $conn -Sql @'
INSERT INTO knowledge_embedding
       (knowledge_object_id, chunk_index, chunk_text, embedding, embedding_model, dimension, chunking_version, content_hash, token_count)
VALUES (@id::uuid, @idx, @text, @vec::vector, @model, @dim, @version, @hash, @tokens)
'@ -Parameters @{
                    id = $stale.Id; idx = $chunkIndex; text = $stale.Chunks[$chunkIndex]
                    vec = $vectorLiteral; model = $contract.EmbeddingModel; dim = $contract.Dimension
                    version = $contract.ChunkingVersion; hash = $stale.ChunkHashes[$chunkIndex]
                    tokens = [int][math]::Ceiling($stale.Chunks[$chunkIndex].Length / 4)
                } | Out-Null
            }
        }

        $estimatedUsd = [math]::Round($embeddingResult.TotalTokens / 1e6 * $contract.UsdPerMillionTokens, 6)
        $tally = [pscustomobject]@{
            objects = @($objects).Count; unchanged = $unchanged; embedded = $staleObjects.Count
            chunks = $totalChunks; tokens = $embeddingResult.TotalTokens; estimatedUsd = $estimatedUsd
        }
        Write-ImperionLog -Level Metric -Source 'vector' -Message 'vectorize: knowledge embedded.' -Data @{
            objects = $tally.objects; unchanged = $tally.unchanged; embedded = $tally.embedded
            chunks = $tally.chunks; tokens = $tally.tokens; estimatedUsd = $tally.estimatedUsd
            provider = 'voyage'; model = $contract.EmbeddingModel; dimension = $contract.Dimension
            chunkingVersion = $contract.ChunkingVersion
            durationSeconds = [math]::Round(((Get-Date) - $runStart).TotalSeconds, 1)
        }
        return $tally
    }
    finally { if ($ownsConnection) { $conn.Dispose() } }
}
