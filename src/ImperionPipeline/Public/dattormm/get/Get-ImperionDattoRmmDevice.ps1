function Get-ImperionDattoRmmDevice {
    <#
    .SYNOPSIS
        Collect Datto RMM managed devices (patch/AV state, asset/software inventory) → bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Datto RMM (issue #195, ADR-0018) — the live device
        inventory: every managed endpoint, its patch state, AV status, and asset/software
        inventory. Datto RMM is a STRONG machine device authority (ADR-0018 §2: the silver
        `device` merge places it `website > datto_rmm > m365 > itglue`) — but that silver merge is
        the CLOUD Pipeline/front-end's concern; THIS collector only writes bronze faithfully. The
        full asset/software inventory is preserved losslessly in raw_payload; the flat columns are
        the device-existence + live-state facts the merge keys on.

        OPERATIONAL DATA → IT GLUE PATH (ADR-0006): Datto RMM describes the managed estate, so the
        downstream silver/relationship layer relates device → IT Glue Organization / Configuration
        / Contact. The bronze collector itself flattens to Postgres; the IT Glue documentation
        write is a separate, scoped/gated step (CLAUDE.md §6) and is NOT performed here.

        AUTH: Datto RMM is an MSP-WIDE vendor credential resolved SecretStore-first /
        Key Vault-fallback by Resolve-ImperionDattoRmmApiKey. The connect helper
        Invoke-ImperionDattoRmmRequest exchanges the API key for a short-lived BEARER (never
        logged) and owns the page-walk. GATED: until the key is provisioned (Mark-gated), the
        resolver throws and the scheduled task logs the gap and exits cleanly (idempotent re-run
        converges).

        TARGET: bronze `datto_rmm_devices` (front-end-owned schema, system CLAUDE.md §1 — migration
        0119 SHIPPED + prod-applied, front-end #674). external_id = the Datto RMM device UID
        (stable) → idempotent upsert. This collector NEVER creates the table; it fails loudly if
        absent (ADR-0005).

        CONFIRM BEFORE LIVE USE: the device field names below are modeled from the documented Datto
        RMM API but UNVERIFIED against the real account until the key lands. Each flat column leads
        with the most likely name and keeps a short fallback chain; an unmatched column lands NULL
        and nothing is lost (full payload in raw_payload) — the KQM/EasyDMARC precedent.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant. (Live per-client tenant
        mapping comes from the Datto RMM site→client mapping — a follow-up once verified against a
        live key; see docs/integrations/datto-rmm.md.)
    .PARAMETER BaseUri
        Datto RMM API origin. Default 'https://api.datto-rmm.com' (placeholder — confirm).
    .PARAMETER ApiKey
        Datto RMM API key override. Defaults to the SecretStore/Key Vault resolution.
    .EXAMPLE
        Get-ImperionDattoRmmDevice | Set-ImperionDattoRmmDeviceToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.datto-rmm.com',
        [string] $ApiKey
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $ApiKey = Resolve-ImperionDattoRmmApiKey -ApiKey $ApiKey

    $devices = Invoke-ImperionDattoRmmRequest -ApiKey $ApiKey -BaseUri $BaseUri `
        -Path '/v2/account/devices' -EntityProperty 'devices'

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionMember).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Datto RMM device fields lead each chain; fallbacks tolerate casing/shape drift.
    # Column set mirrors front-end migration 0119 (datto_rmm_devices).
    $map = [ordered]@{
        device_uid        = { param($d) & $firstOf $d @('uid', 'id', 'deviceUid') }
        hostname          = { param($d) & $firstOf $d @('hostname', 'name', 'deviceName') }
        site_name         = { param($d) & $firstOf $d @('siteName', 'site.name', 'site') }
        operating_system  = { param($d) & $firstOf $d @('operatingSystem', 'os', 'osName') }
        last_seen         = { param($d) & $firstOf $d @('lastSeen', 'lastSeenDate', 'lastLoggedInUser.lastSeen') }
        patch_status      = { param($d) & $firstOf $d @('patchManagement.patchStatus', 'patchStatus', 'patchManagement.status') }
        antivirus_status  = { param($d) & $firstOf $d @('antivirus.antivirusStatus', 'antivirusStatus', 'antivirus.status') }
        agent_version     = { param($d) & $firstOf $d @('agentVersion', 'softwareStatus.agentVersion') }
        device_type       = { param($d) & $firstOf $d @('deviceType.category', 'deviceType', 'type') }
        soft_delete       = { param($d) & $firstOf $d @('softDelete', 'deleted', 'suspended') }
    }

    $devices | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'datto_rmm' -TenantId $TenantId -ExternalIdProperty 'uid'
}
