function Set-ImperionUniFiDeviceToBronze {
    <#
    .SYNOPSIS
        Write flattened UniFi device rows into the unifi_devices bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionUniFiDevice and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the unifi_devices column set
        (name, model, mac, ip_address, site, status, firmware_version, firmware_updatable,
        adopted, last_seen) before the upsert; extras survive in raw_payload.

        The `unifi_devices` table is the front-end-owned bronze table (front-end migration
        0162, #1053/#73; this repo NEVER creates tables, CLAUDE.md §6). It is prod-applied
        but EMPTY until a console is registered in the credential registry — the sweep
        (Invoke-ImperionUniFiDeviceSync) self-gates per console until then. If the table or
        write grant is ever missing, this writer fails loudly at the upsert — by design.

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionUniFiDevice (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to unifi_devices (front-end migration 0162).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionUniFiDevice -ApiKey $key -ConnectionType cloud | Set-ImperionUniFiDeviceToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'unifi_devices'
    )

    begin {
        # unifi_devices column set (front-end migration 0162, #1053/#73): flat columns
        # first, then the standard envelope.
        $tableColumns = @(
            'name', 'model', 'mac', 'ip_address', 'site', 'status',
            'firmware_version', 'firmware_updatable', 'adopted', 'last_seen',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'unifi' -ColumnSet $tableColumns
    }
}
