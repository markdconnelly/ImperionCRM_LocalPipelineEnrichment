function Get-ImperionIntuneManagedApp {
    <#
    .SYNOPSIS
        Collect the per-device Intune detected-app inventory for a tenant and flatten it to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Intune managed-app feed (issue #252; front-end
        ImperionCRM #261 / migration 0148). Reconciles the collector to the schema that actually
        landed: `intune_managed_apps` is the **per-device** app inventory the device-CI detail
        drills into, NOT the tenant-level `mobileApps` catalog the first cut (#143) guessed at.

        Mints an app-only Graph token for the tenant (per-client onboarding app, §3), pages the
        tenant's `/deviceManagement/managedDevices` for the join anchor, then for each device pages
        `/deviceManagement/managedDevices/{id}/detectedApps` and flattens each (device, app) pair to
        the standard bronze envelope. `external_id` is the composite **managed_device_id + app_id**
        (the 0148 PK row id); `managed_device_id` (= `intune_managed_devices.external_id`),
        `serial_number`, and `device_name` are carried as the drill-join keys to the silver device.
        `app_type` is stamped `'detected'` — this feed is the detected-inventory half of the 0148
        `app_type` provenance (the assigned/`'managed'` mobileApp install-status report is a possible
        future feed into the same table).

        LENIENT / CONFIRM-BEFORE-LIVE: the detected-app flat columns map the Graph `detectedApp`
        fields (`displayName` / `version` / `publisher` / `platform` / `sizeInByte`). Fields a
        `detectedApp` does not expose (`install_state`, `install_state_detail`,
        `last_modified_date_time`) land NULL from this feed and stay lossless in `raw_payload`;
        confirm the live payload shape on the first real pull. Returns rows; does not write. Requires
        Initialize-ImperionContext and the application permission DeviceManagementApps.Read.All
        (admin-consent is Mark-gated ops — until granted the Graph call 403s and the run yields
        nothing).
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Client tenants read via the
        per-client onboarding app (§3).
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionIntuneManagedAppToBronze.
    .EXAMPLE
        Get-ImperionIntuneManagedApp | Set-ImperionIntuneManagedAppToBronze
    .EXAMPLE
        Get-ImperionIntuneManagedApp -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId

    # The join anchor: the tenant's Intune managed devices. Trim to the keys the drill join needs
    # (the full device record is its own bronze feed, Get-ImperionM365Device).
    $devices = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices' `
        -AccessToken $token -Select 'id,deviceName,serialNumber'

    # Per-(device, app) flat map onto the 0148 intune_managed_apps column set. Device join keys are
    # spliced onto each app object below; the rest read straight off the Graph detectedApp.
    $map = [ordered]@{
        managed_device_id       = 'managed_device_id'
        serial_number           = 'serial_number'
        device_name             = 'device_name'
        app_id                  = 'id'
        display_name            = 'displayName'
        publisher               = 'publisher'
        version                 = 'version'
        platform                = 'platform'
        # detectedApp carries no install state — null for this feed, populated only by a future
        # assigned/managed mobileApp install-status feed (0148 app_type = 'managed').
        install_state           = 'installState'
        install_state_detail    = 'installStateDetail'
        app_type                = { 'detected' }
        size_in_bytes           = 'sizeInByte'
        last_modified_date_time = 'lastModifiedDateTime'
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($device in $devices) {
        # StrictMode-safe reads (#374): a device/app whose payload omits 'id' must skip the row,
        # NOT throw — a direct `$device.id`/`$app.id` access throws under StrictMode and aborts the
        # whole tenant's app sync (one id-less detectedApp killed 3/4 tenants on 2026-06-26).
        $managedDeviceId = [string](Get-ImperionMember $device 'id')
        if (-not $managedDeviceId) { continue }
        $serialNumber = [string](Get-ImperionMember $device 'serialNumber')
        $deviceName = [string](Get-ImperionMember $device 'deviceName')

        # The per-device detectedApps navigation is exposed in Graph BETA only — v1.0 has no
        # managedDevices/{id}/detectedApps segment (returns 400 "Resource not found for the segment
        # 'detectedApps'"), #369. The managedDevices list above stays v1.0 (it works there).
        $detectedApps = Invoke-ImperionGraphRequest `
            -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$managedDeviceId/detectedApps" `
            -AccessToken $token

        foreach ($app in $detectedApps) {
            $appId = [string](Get-ImperionMember $app 'id')
            if (-not $appId) { continue }

            # Splice the device join context + the composite PK id onto the app object. Add-Member
            # is additive — the full detectedApp payload still flows lossless into raw_payload.
            $appWithDevice = $app | Select-Object *
            $appWithDevice | Add-Member -NotePropertyName 'managed_device_id'     -NotePropertyValue $managedDeviceId -Force
            $appWithDevice | Add-Member -NotePropertyName 'serial_number'         -NotePropertyValue $serialNumber -Force
            $appWithDevice | Add-Member -NotePropertyName 'device_name'           -NotePropertyValue $deviceName -Force
            $appWithDevice | Add-Member -NotePropertyName 'composite_external_id' -NotePropertyValue "$managedDeviceId`:$appId" -Force

            $appWithDevice |
                ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365' -TenantId $TenantId `
                    -ExternalIdProperty 'composite_external_id' |
                ForEach-Object { $rows.Add($_) }
        }
    }

    Write-ImperionLog -Source 'm365' -Message 'Intune detected apps collected.' -Data @{
        devices = @($devices).Count; rows = $rows.Count
    }
    return $rows.ToArray()
}
