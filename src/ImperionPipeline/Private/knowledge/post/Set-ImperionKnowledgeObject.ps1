function Set-ImperionKnowledgeObject {
    <#
    .SYNOPSIS
        Upsert composed knowledge-object rows into the gold `knowledge_object` table.
    .DESCRIPTION
        Post-layer writer for the gold tier (CLAUDE.md §6/§7, ADR-0009; schema = front-end
        migration 0045). Takes the flat rows produced by Get-ImperionKnowledge* and upserts
        on the natural key (tenant_id, entity_type, entity_ref), change-detected on
        content_hash: an unchanged row is not rewritten (and therefore never re-embedded —
        the vectorizer keys off the same hash). Idempotent and resumable; re-running
        converges, never duplicates.

        Pass an open -Connection to share one connection across the knowledge sync;
        otherwise a connection is opened per call (ADR-0003 short-lived token) and disposed.
    .PARAMETER Row
        Flat knowledge_object rows (accepted from the pipeline): tenant_id, entity_type,
        entity_ref, title, body, summary, source, metadata (json text), content_hash.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse.
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionKnowledgeAccount | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        if ($collected.Count -eq 0) {
            Write-ImperionLog -Source 'knowledge' -Message 'knowledge_object: 0 rows to write.'
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("knowledge_object ($($collected.Count) rows)", 'gold upsert')) {
            return [pscustomobject]@{ scanned = $collected.Count; inserted = 0; updated = 0; unchanged = 0 }
        }

        $ownsConnection = $false
        $conn = $Connection
        if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
        try {
            $inserted = 0
            $updated = 0
            $unchanged = 0
            foreach ($record in $collected) {
                $result = Invoke-ImperionDbQuery -Connection $conn -Sql @'
INSERT INTO knowledge_object (tenant_id, entity_type, entity_ref, title, body, summary, source, content_hash, metadata)
VALUES (@tenant, @type, @ref, @title, @body, @summary, @source, @hash, @metadata::jsonb)
ON CONFLICT (tenant_id, entity_type, entity_ref) DO UPDATE
   SET title = EXCLUDED.title, body = EXCLUDED.body, summary = EXCLUDED.summary,
       source = EXCLUDED.source, content_hash = EXCLUDED.content_hash,
       metadata = EXCLUDED.metadata, updated_at = now()
 WHERE knowledge_object.content_hash IS DISTINCT FROM EXCLUDED.content_hash
RETURNING (xmax = 0) AS was_inserted
'@ -Parameters @{
                    tenant = $record.tenant_id; type = $record.entity_type; ref = $record.entity_ref
                    title = $record.title; body = $record.body; summary = $record.summary
                    source = $record.source; hash = $record.content_hash; metadata = $record.metadata
                }
                if (-not $result) { $unchanged++ }
                elseif ($result[0].was_inserted) { $inserted++ }
                else { $updated++ }
            }

            $tally = [pscustomobject]@{
                scanned = $collected.Count; inserted = $inserted; updated = $updated; unchanged = $unchanged
            }
            Write-ImperionLog -Level Metric -Source 'knowledge' -Message 'knowledge_object written.' -Data @{
                scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
            }
            return $tally
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
