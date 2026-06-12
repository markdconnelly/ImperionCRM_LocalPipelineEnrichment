function Set-ImperionITGlueContactToBronze {
    <#
    .SYNOPSIS
        Write flattened IT Glue contact rows into the itglue_contacts bronze table (ADR-0039 shape).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for a table that uses the per-source ADR-0039 shape
        instead of the standard envelope: itglue_contacts (front-end migration 0036) keys on a
        UNIQUE external_ref and stores the raw record in payload_bronze; the silver/gold/match
        columns (contact_id, normalized_silver, summary_gold, …) are filled by the front-end
        merge into the unified contact, not here. So each flat row from
        Get-ImperionITGlueContact is projected down to { external_ref ← external_id,
        payload_bronze ← raw_payload } and upserted on external_ref with -NoChangeDetect (the
        table has no content_hash column; change is resolved at merge time).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the gate/connection/upsert/log/tally; this declares table + shape.
        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionITGlueContact (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to itglue_contacts (front-end migration 0036).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionITGlueContact | Set-ImperionITGlueContactToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'itglue_contacts'
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'itglue' -PerSourceShape
    }
}
