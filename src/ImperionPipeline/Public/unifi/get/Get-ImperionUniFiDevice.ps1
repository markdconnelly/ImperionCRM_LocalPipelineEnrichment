function Get-ImperionUniFiDevice {
    <#
    .SYNOPSIS
        Collect the WHOLE UniFi estate from the cloud Site Manager API with ONE company key and
        flatten every device to a `unifi_devices` bronze row (#321, company-scope remodel).
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6). UniFi is a COMPANY-scope cloud connector (FE #1278 /
        backend #386, ADR-0122): the cloud Site Manager API key (`api.ui.com`) is MSP-wide — one
        key enumerates EVERY client's sites and devices — so this no longer resolves a per-console
        key per client (the dead per-console sweep #259 is retired). It pulls:

          - `GET /v1/sites`   -> sites: `siteId`, `hostId`, `meta.name` (+ statistics). Builds a
                                 hostId -> site display-name map.
          - `GET /v1/devices` -> per-host groups `{ hostId, hostName, devices[] }`. Each device:
                                 `id`, `mac`, `name`, `model`, `ip`, `status`, `version`,
                                 `firmwareStatus`, `isConsole`, `isManaged`, `adoptionTime`, ...

        Each device's owning **site** is the `meta.name` of the site whose `hostId` matches the
        device's host group (falling back to the group's `hostName`). The site name is BOTH the
        client-mapping unit key and its display label (the FE `listClientMappingUnits` keys UniFi
        on the `site` column), so an admin maps each discovered site -> account in the GUI.

        ACCOUNT STAMPING. The bronze envelope `tenant_id` must let the co-located merge
        (Invoke-ImperionUniFiMerge, #284) resolve a device to its account. The merge resolves
        `tenant_id` as an `account.id` directly, so this stamps each device's `tenant_id` with the
        owning **account id** from the GUI site->account mapping passed in via -SiteAccountMap
        (`entity_xref(entity_type='account', source_system='unifi', source_key=<site>)`). A device
        whose site is not yet mapped is stamped with the all-zero sentinel uuid -UnmappedTenantId:
        a valid uuid (so the merge's `tenant_id::uuid` cast never throws) that resolves to NO
        account (the merge counts it unmapped) — it still lands in bronze so the GUI surfaces the
        site for mapping. The site is re-stamped to the real account on the next run once mapped.

        AUTH: takes one explicit company `-ApiKey` (the resolved `conn-company-unifi` Site Manager
        key) and holds no secret — pure and mockable. Sent as `X-API-Key` by
        Invoke-ImperionUniFiRequest. Returns flat rows; does not write. Requires
        Initialize-ImperionContext.

        API SHAPE confirmed against api.ui.com/v1 (secret-safe probe, 2026-06-24): envelope
        `{ data, httpStatusCode, traceId }`; the flat column field names below are the live device
        shape, not the earlier doc-guess.
    .PARAMETER ApiKey
        The company UniFi Site Manager API key (resolved from `conn-company-unifi`), sent as X-API-Key.
    .PARAMETER SiteAccountMap
        Hashtable site-name -> owning account id (uuid), from the GUI `entity_xref('account',
        'unifi', site)` mappings. A device on an unmapped site is stamped -UnmappedTenantId.
    .PARAMETER UnmappedTenantId
        Sentinel `tenant_id` for a device whose site is not yet mapped. Defaults to the all-zero
        uuid (a valid uuid that resolves to no account — the merge counts it unmapped).
    .EXAMPLE
        $key = Resolve-ImperionCompanyCredential -Provider 'unifi' -Field 'apiKey'
        Get-ImperionUniFiDevice -ApiKey $key -SiteAccountMap $siteAccountMap | Set-ImperionUniFiDeviceToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [hashtable] $SiteAccountMap = @{},
        [string] $UnmappedTenantId = '00000000-0000-0000-0000-000000000000'
    )

    # Flat columns target the `unifi_devices` bronze (FE migration 0162, #1053/#73). Field names
    # are the CONFIRMED Site Manager device shape (#321 probe): mac/ip/status/version/
    # firmwareStatus/adoptionTime — NOT the earlier macAddress/ipAddress/state/... doc-guesses.
    # `site` reads the NoteProperty stamped below. The Site Manager device has no last-seen field
    # today, so `last_seen` maps to an absent property (-> null); it is preserved in raw_payload.
    $map = [ordered]@{
        name               = 'name'
        model              = 'model'
        mac                = 'mac'
        ip_address         = 'ip'
        site               = { param($device) Get-ImperionMember $device 'site' }
        status             = 'status'
        firmware_version   = 'version'
        firmware_updatable = 'firmwareStatus'
        adopted            = 'adoptionTime'
        last_seen          = 'lastSeen'
    }

    # 1) Sites: hostId -> human site name (meta.name). The site name is the client-mapping key.
    $sites = Invoke-ImperionUniFiRequest -ApiKey $ApiKey -Uri 'https://api.ui.com/v1/sites'
    $siteNameByHost = @{}
    foreach ($site in $sites) {
        $hostId = Get-ImperionMember $site 'hostId'
        $siteName = Get-ImperionPropertyPath -InputObject $site -Path 'meta.name'
        if ($hostId -and $siteName -and -not $siteNameByHost.ContainsKey([string]$hostId)) {
            $siteNameByHost[[string]$hostId] = [string]$siteName
        }
    }

    # 2) Devices: per-host groups; flatten each device under its site, stamping the owning account.
    $hostGroups = Invoke-ImperionUniFiRequest -ApiKey $ApiKey -Uri 'https://api.ui.com/v1/devices'
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $hostGroups) {
        $hostId = Get-ImperionMember $group 'hostId'
        $hostName = Get-ImperionMember $group 'hostName'
        $siteName = if ($hostId -and $siteNameByHost.ContainsKey([string]$hostId)) {
            $siteNameByHost[[string]$hostId]
        }
        else { [string]$hostName }

        # The merge resolves this account id directly; an unmapped site -> sentinel (counts unmapped).
        $tenantId = if ($siteName -and $SiteAccountMap.ContainsKey([string]$siteName)) {
            [string]$SiteAccountMap[[string]$siteName]
        }
        else { $UnmappedTenantId }

        $groupDevices = Get-ImperionMember $group 'devices'
        if ($null -eq $groupDevices) { $groupDevices = $group }   # flat shape fallback
        foreach ($device in $groupDevices) {
            if ($null -eq $device) { continue }
            # Stamp the owning site so the flat row carries it (the device payload does not).
            $device | Add-Member -NotePropertyName 'site' -NotePropertyValue $siteName -Force
            $flat = $device | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'unifi' `
                -TenantId $tenantId -ExternalIdProperty 'id'
            $rows.Add($flat)
        }
    }

    Write-ImperionLog -Source 'unifi' -Message 'UniFi devices collected (company Site Manager key).' -Data @{
        sites = @($sites).Count; devices = $rows.Count
    }
    return $rows.ToArray()
}
