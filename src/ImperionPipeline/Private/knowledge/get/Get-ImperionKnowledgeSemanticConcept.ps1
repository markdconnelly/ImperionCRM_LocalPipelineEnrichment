function Get-ImperionKnowledgeSemanticConcept {
    <#
    .SYNOPSIS
        Compose a gold `semantic_concept` knowledge object per OKF concept file in the bundle.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009) that turns the
        front-end OKF semantic-layer bundle into recall-able gold (LP issue #176; front-end
        ADR-0086 bundle / ADR-0041 vector contract). A human-edited semantic corpus — what each
        silver entity *means*, its source-of-record/authority, its joins — is far better agent
        RAG context than raw schema dumps, so the orchestrator can ground on curated meaning.

        Input is the LOCAL bundle the front end owns (resolved by Resolve-ImperionOkfBundle —
        this repo never forks the canon, CLAUDE.md section 11). For every
        `<BundlePath>/tables/<concept>.md` this emits ONE flat knowledge_object row
        (`entity_type='semantic_concept'`, `entity_ref=<concept>`): `title` from frontmatter,
        `body` = the concept prose (frontmatter stripped), `metadata` = the frontmatter facets +
        the source-doc back-reference, `content_hash` over title+body (the SAME idempotency key
        Set-ImperionKnowledgeObject and the vectorizer honour, so an unchanged concept never
        re-composes and never re-embeds, §7). The normal vectorizer then chunks + embeds these
        rows like any other knowledge_object.

        Reads the filesystem (not the DB), so it does not use the DB compose spine
        (Invoke-ImperionKnowledgeCompose) — but it emits the identical row shape.

        SAFE BY DESIGN: the bundle is PII-free by the ADR-0086 conformance rules (definitions,
        not row data; no client identifiers, no secrets), so only the curated docs are embedded —
        never row-level prod data. Pure text parsing; no network.
    .PARAMETER BundlePath
        The resolved semantic-layer directory (the one containing tables/). Use
        Resolve-ImperionOkfBundle to obtain it.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant — the bundle is company-wide canon
        knowledge, not client-tenant data.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeSemanticConcept -BundlePath $b | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $BundlePath,
        [string] $TenantId
    )

    if (-not $TenantId) { $TenantId = (Get-ImperionConfig).PartnerTenantId }

    $tablesPath = Join-Path $BundlePath 'tables'
    if (-not (Test-Path $tablesPath)) {
        Write-ImperionLog -Source 'knowledge' -Message "knowledge semantic concepts: no bundle tables dir at '$tablesPath'."
        return @()
    }

    $conceptFiles = @(Get-ChildItem -LiteralPath $tablesPath -Filter '*.md' -File | Sort-Object Name)
    if ($conceptFiles.Count -eq 0) {
        Write-ImperionLog -Source 'knowledge' -Message 'knowledge semantic concepts: bundle has no concept files.'
        return @()
    }

    $rows = foreach ($conceptFile in $conceptFiles) {
        $concept = [System.IO.Path]::GetFileNameWithoutExtension($conceptFile.Name)
        $lines = Get-Content -LiteralPath $conceptFile.FullName -ErrorAction Stop

        # Split frontmatter (between the first two '---' fences) from the concept prose.
        $frontmatter = [System.Collections.Generic.List[string]]::new()
        $bodyLines = [System.Collections.Generic.List[string]]::new()
        $fence = 0
        foreach ($line in $lines) {
            if ($fence -lt 2 -and $line.Trim() -eq '---') { $fence++; continue }
            if ($fence -lt 2) { $frontmatter.Add($line) } else { $bodyLines.Add($line) }
        }
        # A file with no frontmatter fences keeps its whole content as the body.
        if ($fence -lt 2) { $bodyLines = [System.Collections.Generic.List[string]]($lines); $frontmatter.Clear() }

        $field = {
            param($name)
            foreach ($frontLine in $frontmatter) {
                if ($frontLine -match "^\s*$([regex]::Escape($name)):\s*(.+?)\s*$") { return $Matches[1] }
            }
            return $null
        }

        $title = & $field 'title'
        if (-not $title) { $title = $concept }
        $description = & $field 'description'
        $conceptType = & $field 'type'
        $timestamp = & $field 'timestamp'
        $tagsRaw = & $field 'tags'
        $tags = if ($tagsRaw) {
            @($tagsRaw.Trim().TrimStart('[').TrimEnd(']') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        else { @() }

        $body = (($bodyLines -join "`n").Trim())
        if (-not $body) {
            Write-ImperionLog -Source 'knowledge' -Message "knowledge semantic concepts: '$concept' has no prose body; skipped."
            continue
        }

        $metadata = @{
            concept     = $concept
            title       = $title
            description = $description
            okf_type    = $conceptType
            tags        = $tags
            timestamp   = $timestamp
            source_doc  = "docs/database/semantic-layer/tables/$concept.md"
        }

        $row = [pscustomobject]@{
            tenant_id    = $TenantId
            entity_type  = 'semantic_concept'
            entity_ref   = $concept
            title        = $title
            body         = $body
            summary      = $description
            source       = 'okf_semantic_layer'
            metadata     = ($metadata | ConvertTo-Json -Compress)
            content_hash = $null
        }
        $row.content_hash = Get-ImperionContentHash -InputObject @{ title = $row.title; body = $row.body }
        $row
    }

    $rows = @($rows | Where-Object { $null -ne $_ })
    Write-ImperionLog -Level Metric -Source 'knowledge' -Message 'knowledge semantic concepts composed.' -Data @{ 'semantic concepts' = $rows.Count }
    return $rows
}
