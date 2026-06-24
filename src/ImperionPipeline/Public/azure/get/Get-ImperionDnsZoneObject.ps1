function Get-ImperionDnsZoneObject {
    <#
    .SYNOPSIS
        Collect Azure DNS zones + their recordsets from a subscription and flatten to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for DNS posture, the Azure manage plane of
        front-end ADR-0063 (issue #155 / front-end migration 0080). Mints an ARM token
        (Reader), pages /subscriptions/{id}/providers/Microsoft.Network/dnsZones, and for
        each zone: probes whether THIS identity can write recordsets at the zone scope
        (Test-ImperionArmWriteAccess — the 'manageable' proof, read-only), then pages the
        zone's recordsets (the authoritative record state, plane 'azure').

        Emits two row kinds, each stamped with an `entity` discriminator that
        Set-ImperionDnsZoneToBronze routes on (and projects away — neither table has an
        `entity` column):
          - entity 'zones'   -> dns_zones   (one row per zone: domain, in_azure, manageable,
                                resource_group, subscription_id, ns_records, verdict)
          - entity 'records' -> dns_records (one row per recordset: domain, plane='azure',
                                record_type, name, value, ttl)

        The zone `verdict` here is the manage-plane reading only — 'managed' (write proven)
        or 'in-azure-readonly'. The final not-in-azure|in-azure-readonly|managed verdict
        (which also requires live NS delegation to the zone) is computed by the silver
        drift merge (local #157); public-plane records come from the resolver collector
        (#156). Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER SubscriptionId
        The subscription to enumerate (from Get-ImperionAzureSubscription).
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .PARAMETER ApiVersion
        ARM api-version for the DNS zone + recordset reads. Default 2018-05-01.
    .OUTPUTS
        Flat bronze rows (source 'dns') ready for Set-ImperionDnsZoneToBronze.
    .EXAMPLE
        Get-ImperionDnsZoneObject -SubscriptionId $sub | Set-ImperionDnsZoneToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $SubscriptionId,
        [string] $TenantId,
        [string] $ApiVersion = '2018-05-01'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionArmToken -TenantId $TenantId
    $zones = Invoke-ImperionArmRequest -AccessToken $token `
        -Path "/subscriptions/$SubscriptionId/providers/Microsoft.Network/dnsZones?api-version=$ApiVersion"

    $rows = [System.Collections.Generic.List[object]]::new()
    $zoneCount = 0
    $recordCount = 0

    foreach ($zone in $zones) {
        $zoneCount++
        $zoneId = Get-ImperionMember $zone 'id'
        $domain = Get-ImperionMember $zone 'name'
        $zoneProps = Get-ImperionMember $zone 'properties'
        $nameServers = @(Get-ImperionMember $zoneProps 'nameServers') | Where-Object { $_ }
        $resourceGroup = if ($zoneId -match '/resourceGroups/([^/]+)') { $Matches[1] } else { $null }

        # A zone with no/empty id can't be probed (the mandatory -Scope bind throws) and can't
        # form a valid bronze row (external_id = id). Skip + log it so one malformed zone never
        # aborts the whole sync via the surrounding try/catch (#323; idempotency/resumability, §6).
        if (-not $zoneId) {
            Write-ImperionLog -Level Warn -Source 'dns' `
                -Message 'DNS zone with empty id; skipping.' -Data @{ tenant = $TenantId; subscription = $SubscriptionId; domain = $domain }
            continue
        }

        # 'manageable' = the SP's own effective permissions allow a recordset write at this
        # zone scope (ADR-0063). Proof, read-only — no role-assignment guesswork.
        $manageable = Test-ImperionArmWriteAccess -Scope $zoneId -AccessToken $token
        $verdict = if ($manageable) { 'managed' } else { 'in-azure-readonly' }

        $zoneMap = [ordered]@{
            entity          = { 'zones' }
            domain          = { $domain }
            in_azure        = { 'true' }
            manageable      = { if ($manageable) { 'true' } else { 'false' } }
            resource_group  = { $resourceGroup }
            subscription_id = { $SubscriptionId }
            ns_records      = { $nameServers -join '; ' }
            verdict         = { $verdict }
        }
        $zone | ConvertTo-ImperionFlatObject -PropertyMap $zoneMap -Source 'dns' `
            -TenantId $TenantId -ExternalIdProperty 'id' | ForEach-Object { $rows.Add($_) }

        # Azure-plane recordsets — the authoritative record state for drift.
        $recordsets = Invoke-ImperionArmRequest -AccessToken $token `
            -Path "$zoneId/recordsets?api-version=$ApiVersion"
        foreach ($recordset in $recordsets) {
            $recordCount++
            $recordType = (([string](Get-ImperionMember $recordset 'type')) -split '/')[-1]
            $recordName = Get-ImperionMember $recordset 'name'
            $recordProps = Get-ImperionMember $recordset 'properties'
            $ttl = Get-ImperionMember $recordProps 'TTL'
            $recordValue = ConvertTo-ImperionDnsRecordValue -RecordType $recordType -Properties $recordProps
            # Composite, stable record identity (no single natural id on a recordset).
            $externalId = '{0}|azure|{1}|{2}' -f $domain, $recordType, $recordName
            $recordset | Add-Member -NotePropertyName _imperion_external_id -NotePropertyValue $externalId -Force

            $recordMap = [ordered]@{
                entity      = { 'records' }
                domain      = { $domain }
                plane       = { 'azure' }
                record_type = { $recordType }
                name        = { $recordName }
                value       = { $recordValue }
                ttl         = { if ($null -ne $ttl) { [string]$ttl } else { $null } }
            }
            $recordset | ConvertTo-ImperionFlatObject -PropertyMap $recordMap -Source 'dns' `
                -TenantId $TenantId -ExternalIdProperty '_imperion_external_id' | ForEach-Object { $rows.Add($_) }
        }
    }

    Write-ImperionLog -Source 'dns' -Message 'Azure DNS zones + recordsets collected.' -Data @{
        subscription = $SubscriptionId; zones = $zoneCount; records = $recordCount; rows = $rows.Count
    }
    return $rows.ToArray()
}
