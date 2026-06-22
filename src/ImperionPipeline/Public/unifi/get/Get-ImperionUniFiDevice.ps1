function Get-ImperionUniFiDevice {
    <#
    .SYNOPSIS
        Collect UniFi network devices (inventory + config-compliance signals) and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for issue #73's locked design (2026-06-10): two
        UniFi API families, chosen per site topology, one flat output shape:

        - **-ConnectionType console** (site WITH a gateway/console): Network Integration
          API on the customer's console — enumerates `/sites` then
          `/sites/{siteId}/devices` under
          `https://<ControllerHost>/proxy/network/integration/v1`.
        - **-ConnectionType cloud** (site WITHOUT a gateway): Site Manager API —
          `https://api.ui.com/v1/devices` (devices grouped per host).

        AUTH: this is the per-console PRIMITIVE — it takes one explicit `-ApiKey` and holds
        no secret. UniFi keys are per-client, per-console credentials in the front-end
        `connection` registry (ADR-0103); the scheduled fan-out Invoke-ImperionUniFiDeviceSync
        (#259) resolves each console's key from the registry and calls this once per console.

        Flat columns target the `unifi_devices` bronze table (front-end migration 0162,
        #1053/#73; see docs/integrations/unifi.md): name, model, mac, ip_address, site,
        status, firmware_version, firmware_updatable (the config-compliance signal: an
        available but unapplied firmware/config update), adopted, last_seen. Everything else
        stays lossless in raw_payload.

        CONFIRM BEFORE LIVE USE: endpoint paths, paging, and field names are ASSUMPTIONS
        from the published UniFi API docs — verify per connection type on the first pull.
        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER ApiKey
        UniFi API key for this console (per-client/per-console registry credential), sent as X-API-Key.
    .PARAMETER ConnectionType
        'console' (Network Integration API on the customer console) or 'cloud'
        (Site Manager API at api.ui.com).
    .PARAMETER ControllerHost
        Console hostname/IP (required for -ConnectionType console).
    .PARAMETER TenantId
        Owning customer tenant stamped on each row; defaults to the partner tenant.
    .EXAMPLE
        Get-ImperionUniFiDevice -ApiKey $key -ConnectionType console -ControllerHost 'unifi.acme.local'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][ValidateSet('console', 'cloud')][string] $ConnectionType,
        [string] $ControllerHost,
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $map = [ordered]@{
        name               = 'name'
        model              = 'model'
        mac                = 'macAddress'
        ip_address         = 'ipAddress'
        site               = { param($device) Get-ImperionMember $device 'site' }
        status             = 'state'
        firmware_version   = 'firmwareVersion'
        firmware_updatable = 'firmwareUpdatable'
        adopted            = 'adoptedAt'
        last_seen          = 'lastSeen'
    }

    if ($ConnectionType -eq 'console') {
        if (-not $ControllerHost) { throw 'Get-ImperionUniFiDevice: -ControllerHost is required for -ConnectionType console.' }
        $base = 'https://{0}/proxy/network/integration/v1' -f $ControllerHost.TrimEnd('/')

        $sites = Invoke-ImperionUniFiRequest -ApiKey $ApiKey -Uri "$base/sites"
        $devices = foreach ($site in $sites) {
            $siteId = Get-ImperionMember $site 'id'
            $siteName = Get-ImperionMember $site 'name'
            foreach ($device in (Invoke-ImperionUniFiRequest -ApiKey $ApiKey -Uri "$base/sites/$siteId/devices")) {
                # Stamp the owning site so the flat row carries it (the device payload may not).
                $device | Add-Member -NotePropertyName 'site' -NotePropertyValue $siteName -Force -PassThru
            }
        }
    }
    else {
        # Cloud Site Manager: devices come grouped per host; each group's `devices` array
        # holds the actual records (assumption — confirm on first pull).
        $hostGroups = Invoke-ImperionUniFiRequest -ApiKey $ApiKey -Uri 'https://api.ui.com/v1/devices'
        $devices = foreach ($hostGroup in $hostGroups) {
            $hostName = Get-ImperionPropertyPath -InputObject $hostGroup -Path 'hostName'
            $groupDevices = Get-ImperionMember $hostGroup 'devices'
            if ($null -eq $groupDevices) { $groupDevices = $hostGroup }   # flat shape fallback
            foreach ($device in $groupDevices) {
                $device | Add-Member -NotePropertyName 'site' -NotePropertyValue $hostName -Force -PassThru
            }
        }
    }

    $rows = @($devices | Where-Object { $_ } | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'unifi' -TenantId $TenantId -ExternalIdProperty 'id')
    Write-ImperionLog -Source 'unifi' -Message 'UniFi devices collected.' -Data @{
        connection_type = $ConnectionType; devices = @($rows).Count
    }
    return $rows
}
