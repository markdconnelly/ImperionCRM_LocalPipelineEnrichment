function Set-ImperionM365DeviceToBronze {
    <#
    .SYNOPSIS
        Write flattened Intune managed-device rows into the m365_devices bronze table (ADR-0039 shape).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for a table that uses the per-source ADR-0039 shape
        instead of the standard envelope: m365_devices (front-end migration 0036) keys on a
        UNIQUE external_ref and stores the raw record in payload_bronze; the silver/gold/match
        columns (device_id, normalized_silver, summary_gold, …) are filled by the front-end
        merge into the unified device, not here. So each flat row from Get-ImperionM365Device is
        projected down to { external_ref ← external_id, payload_bronze ← raw_payload } and
        upserted on external_ref with -NoChangeDetect (the table has no content_hash column;
        change is resolved at merge time).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the gate/connection/upsert/log/tally; this declares table + shape.
        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionM365Device (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to m365_devices (front-end migration 0036).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionM365Device -TenantId $customerTenantId | Set-ImperionM365DeviceToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'm365_devices'
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'm365' -PerSourceShape
    }
}
