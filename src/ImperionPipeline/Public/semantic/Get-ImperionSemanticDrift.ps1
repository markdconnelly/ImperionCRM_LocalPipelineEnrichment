function Get-ImperionSemanticDrift {
    <#
    .SYNOPSIS
        Detect drift between the live silver schema and the front-end OKF semantic-layer bundle.
    .DESCRIPTION
        For each catalog entry (Get-ImperionSemanticCatalog) compares the live silver relation's
        column NAMES (Get-ImperionSilverSchema — metadata only, never row data, never PII) to the
        columns documented in the matching OKF concept file (Get-ImperionOkfConcept). Classifies
        each concept:
          in-sync          — documented columns match AND the authority rule is stated
          drift            — relation exists + concept exists, but the column sets differ
          missing-concept  — live silver relation exists but has NO concept file (needs authoring)
          orphaned-concept — concept file exists but the live relation is gone/renamed
          missing-authority — columns match but the concept states NO source-of-record / authority
                              rule (ADR-0104 §6 layer 3 — the section the orchestrator grounds on)

        Returns one row per catalog entry with the column deltas (AddedColumns = live-but-undocumented,
        RemovedColumns = documented-but-gone) so a caller can draft a precise bundle-update proposal.

        Read-only and PII-free by construction: only column NAMES cross the boundary. This is the
        DETECTION core for issue #175 / ADR-0086; opening the cross-repo proposal is a separate,
        gated step (Invoke-ImperionSemanticDriftSync).
    .PARAMETER BundlePath
        Path to the local checkout of markdconnelly/ImperionCRM's docs/database/semantic-layer
        directory (the agent clones/pulls it read-only; it is the front end's canon, never forked
        here — CLAUDE.md section 11).
    .PARAMETER Concept
        Optional single concept key (e.g. 'expense_item'); default evaluates the whole catalog.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Get-ImperionSemanticDrift -BundlePath $b | Where-Object status -ne 'in-sync'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $BundlePath,
        [string] $Concept,
        $Connection
    )

    $catalog = Get-ImperionSemanticCatalog
    if ($Concept) { $catalog = @($catalog | Where-Object Concept -eq $Concept) }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($c in $catalog) {
            $live = Get-ImperionSilverSchema -Connection $Connection -Relation $c.Relation
            $file = Join-Path (Join-Path $BundlePath 'tables') ("{0}.md" -f $c.Concept)
            $doc = Get-ImperionOkfConcept -Path $file

            $liveSet = [string[]]@($live | ForEach-Object { $_.ToLowerInvariant() })
            $docSet = [string[]]@($doc.Columns)

            $added = [string[]]@($liveSet | Where-Object { $docSet -notcontains $_ })       # live, undocumented
            $removed = [string[]]@($docSet | Where-Object { $liveSet -notcontains $_ })     # documented, gone

            $status =
                if ($liveSet.Count -eq 0 -and $doc.Exists) { 'orphaned-concept' }
                elseif ($liveSet.Count -eq 0) { 'in-sync' }                                 # not in catalog scope yet
                elseif (-not $doc.Exists) { 'missing-concept' }
                elseif ($added.Count -eq 0 -and $removed.Count -eq 0) {
                    # Columns match; the authority rule is the remaining dimension (ADR-0104 §6).
                    if ($doc.HasAuthority) { 'in-sync' } else { 'missing-authority' }
                }
                else { 'drift' }

            $results.Add([pscustomobject]@{
                    concept         = $c.Concept
                    relation        = $c.Relation
                    status          = $status
                    added_columns   = $added      # live but undocumented
                    removed_columns = $removed    # documented but gone
                    has_authority   = $doc.HasAuthority
                    doc_timestamp   = $doc.Timestamp
                })
        }
        return $results.ToArray()
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
