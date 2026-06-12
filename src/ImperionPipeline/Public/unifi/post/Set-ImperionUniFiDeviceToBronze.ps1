function Set-ImperionUniFiDeviceToBronze {
    <#
    .SYNOPSIS
        Write flattened UniFi device rows into the unifi_devices bronze table (PENDING front-end migration).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionUniFiDevice and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the PROPOSED unifi_devices
        column set (name, model, mac, ip_address, site, status, firmware_version,
        firmware_updatable, adopted, last_seen) before the upsert; extras survive in
        raw_payload.

        SCHEMA GATE (issue #73): the `unifi_devices` table does NOT exist yet — it needs a
        front-end migration via the schema-handoff process (proposed DDL in
        docs/integrations/unifi.md; this repo NEVER creates tables, CLAUDE.md §6). Until
        that migration lands and the SP is granted write, this writer fails loudly at the
        upsert — by design.

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionUniFiDevice (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to unifi_devices (front-end migration pending).
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
        # PROPOSED unifi_devices column set (front-end migration pending — issue #73 schema
        # handoff): flat columns first, then the standard envelope.
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
