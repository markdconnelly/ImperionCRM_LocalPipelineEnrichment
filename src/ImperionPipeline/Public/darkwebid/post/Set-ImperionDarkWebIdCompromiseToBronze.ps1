function Set-ImperionDarkWebIdCompromiseToBronze {
    <#
    .SYNOPSIS
        Write flattened Dark Web ID compromise rows into the darkwebid_exposures bronze table (ADR-0039 shape).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the per-source ADR-0039 shape (front-end migration
        0043 / ADR-0040): darkwebid_exposures keys on a UNIQUE external_ref and stores the raw
        record in payload_bronze; the silver/gold/match columns are filled by the front-end
        merge into credential_exposure, not here. Each flat row from
        Get-ImperionDarkWebIdCompromise is projected to { external_ref ← external_id,
        payload_bronze ← raw_payload } and upserted on external_ref with -NoChangeDetect (no
        content_hash column; change is resolved at merge time).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the gate/connection/upsert/log/tally; this declares table + shape.
        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionDarkWebIdCompromise (from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to darkwebid_exposures (front-end migration 0043).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionDarkWebIdCompromise -ApiKey $key -Domain 'acme.com' | Set-ImperionDarkWebIdCompromiseToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'darkwebid_exposures'
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'darkwebid' -PerSourceShape
    }
}
