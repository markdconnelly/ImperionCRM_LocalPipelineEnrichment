function Set-ImperionIntuneManagedDeviceToBronze {
    <#
    .SYNOPSIS
        Write flattened Intune managedDevice rows into the intune_managed_devices bronze table (PENDING front-end migration).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the device-compliance feed (issue #75 /
        front-end ADR-0051 decision 6): Intune `managedDevices` land **per device,
        unreduced** — flat compliance columns (complianceState, lastSyncDateTime,
        enrollment, OS/version, join keys) queryable for the device page, full payload
        lossless in raw_payload. This is the ONLY source of device-level posture
        indicators (tenant-level classification is never proxied to devices) and the
        seed of the future vulnerability/endpoint pillar. The merge joins to silver
        `device` by serial / Entra device id (front-end/pipeline work).

        DISTINCT from Set-ImperionM365DeviceToBronze: that one feeds the ADR-0039
        per-source `m365_devices` shape for the device-identity merge; THIS one feeds
        the posture-grade flat table. Same collector (Get-ImperionM365Device) drives both.

        SCHEMA GATE (issue #75): the `intune_managed_devices` table does NOT exist yet —
        front-end migration via the schema-handoff process (proposed DDL in the issue
        comment; this repo NEVER creates tables, CLAUDE.md §6). Until it lands and the SP
        is granted write, this writer fails loudly at the upsert — by design.

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable, change-detected. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionM365Device (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to intune_managed_devices (front-end migration pending).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionM365Device | Set-ImperionIntuneManagedDeviceToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'intune_managed_devices'
    )

    begin {
        # PROPOSED intune_managed_devices column set (front-end migration pending — issue
        # #75 schema handoff): the collector's full flat map (compliance + identity + join
        # keys), then the standard envelope.
        $tableColumns = @(
            'device_name', 'managed_device_name', 'os', 'os_version', 'compliance_state',
            'management_state', 'manufacturer', 'model', 'serial_number', 'imei',
            'wifi_mac_address', 'azure_ad_device_id', 'user_principal_name',
            'user_display_name', 'email_address', 'ownership', 'enrolled_date_time',
            'last_sync_date_time', 'is_encrypted', 'device_category',
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
