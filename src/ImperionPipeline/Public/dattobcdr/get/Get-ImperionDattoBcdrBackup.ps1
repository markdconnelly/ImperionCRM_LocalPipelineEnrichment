function Get-ImperionDattoBcdrBackup {
    <#
    .SYNOPSIS
        Collect Datto BCDR per-device backup posture (protected/last-good-backup) → bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Datto BCDR / backup (issue #195, ADR-0018) — the
        answer to "is this machine actually recoverable?": protected / unprotected, last-good
        backup, last-screenshot-verification, per device. The grain is device backup posture;
        external_id (and the join to the device record) is the Datto `device_uid` (ADR-0018 §1:
        "joins on device_uid"). The downstream silver merge contributes these backup-posture fields
        to the unified `device` (ADR-0018 §2 field-scoped merge) — a CLOUD Pipeline/front-end
        concern, NOT done here.

        OPERATIONAL DATA → IT GLUE PATH (ADR-0006): backup posture relates to the same
        device/Configuration in IT Glue; that documentation write is a separate, scoped/gated step
        (CLAUDE.md §6) and is NOT performed by this bronze collector.

        AUTH: Datto BCDR is an MSP-WIDE vendor credential resolved SecretStore-first /
        Key Vault-fallback by Resolve-ImperionDattoBcdrApiKey and sent as an Authorization: Bearer
        header (URLs are NOT secret-bearing). GATED: until the key is provisioned (Mark-gated), the
        resolver throws and the scheduled task logs the gap and exits cleanly.

        TARGET: bronze `datto_bcdr_backups` (front-end-owned schema, migration 0119 SHIPPED +
        prod-applied, front-end #674). external_id = the Datto device UID (stable) → idempotent
        upsert. NEVER creates the table; fails loudly if absent (ADR-0005).

        CONFIRM BEFORE LIVE USE: the field names below are modeled from the documented Datto API
        but UNVERIFIED until the key lands. Each flat column keeps a fallback chain; misses land
        NULL and raw_payload is lossless (the KQM/EasyDMARC precedent).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (live per-client mapping
        is a follow-up — see docs/integrations/datto-bcdr.md).
    .PARAMETER BaseUri
        Datto BCDR API origin. Default 'https://api.datto.com' (placeholder — confirm).
    .PARAMETER ApiKey
        Datto BCDR API key override. Defaults to the SecretStore/Key Vault resolution.
    .EXAMPLE
        Get-ImperionDattoBcdrBackup | Set-ImperionDattoBcdrBackupToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.datto.com',
        [string] $ApiKey
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $ApiKey = Resolve-ImperionDattoBcdrApiKey -ApiKey $ApiKey

    $uri = '{0}/v1/bcdr/agents' -f $BaseUri.TrimEnd('/')
    $agents = Invoke-ImperionDattoBcdrRequest -ApiKey $ApiKey -Uri $uri

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionMember).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Datto BCDR agent/backup fields lead each chain; column set mirrors front-end
    # migration 0119 (datto_bcdr_backups). external_id (and the device join) is device_uid.
    $map = [ordered]@{
        device_uid          = { param($a) & $firstOf $a @('deviceUid', 'agentUid', 'uid', 'id') }
        protected_status    = { param($a) & $firstOf $a @('protectedStatus', 'protected', 'backupStatus') }
        last_backup_at      = { param($a) & $firstOf $a @('lastBackup', 'lastSnapshot', 'lastBackupTimestamp') }
        last_good_backup_at = { param($a) & $firstOf $a @('lastGoodBackup', 'lastSuccessfulBackup', 'lastGoodSnapshot') }
        backup_type         = { param($a) & $firstOf $a @('backupType', 'agentType', 'type') }
        agent_version       = { param($a) & $firstOf $a @('agentVersion', 'version') }
    }

    $agents | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'datto_bcdr' -TenantId $TenantId -ExternalIdProperty 'deviceUid'
}
