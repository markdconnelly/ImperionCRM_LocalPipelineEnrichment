function Set-ImperionIntuneManagedAppToBronze {
    <#
    .SYNOPSIS
        Write flattened Intune per-device app rows into the intune_managed_apps bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the Intune managed-app feed (issue #252 / front-end
        ImperionCRM #261 / migration 0148): the per-device detected/managed app inventory lands
        **one row per (device, app)** — flat join keys (`managed_device_id` / `serial_number` /
        `device_name`) + app identity/state columns queryable for the device-CI drill-in, full
        payload lossless in `raw_payload`. PK `(tenant_id, source, external_id)` with `external_id`
        = managed_device_id + app_id (set by the collector).

        Front-end migration 0148 (`intune_managed_apps`) is applied to prod, so the only remaining
        gate is the Graph `DeviceManagementApps.Read.All` admin consent on the collector side
        (Mark-gated ops). This writer is deploy-ahead safe regardless: if the table or the
        `imperion-localpipeline` write grant is ever absent it fails loudly at the upsert rather
        than silently dropping rows (CLAUDE.md §6 — this repo never creates tables).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold) using -ColumnSet, so a
        future collector field can never break the insert (extra props survive in raw_payload;
        missing ones land NULL). Idempotent/resumable, change-detected. Pass an open -Connection to
        share one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionIntuneManagedApp (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to intune_managed_apps (front-end migration 0148).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionIntuneManagedApp | Set-ImperionIntuneManagedAppToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'intune_managed_apps'
    )

    begin {
        # intune_managed_apps column set (front-end migration 0148): per-device join keys, the app
        # identity/state columns, then the standard envelope. Mirrors the migration 1:1.
        $tableColumns = @(
            'managed_device_id', 'serial_number', 'device_name',
            'app_id', 'display_name', 'publisher', 'version', 'platform',
            'install_state', 'install_state_detail', 'app_type',
            'size_in_bytes', 'last_modified_date_time',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'm365' -ColumnSet $tableColumns
    }
}
