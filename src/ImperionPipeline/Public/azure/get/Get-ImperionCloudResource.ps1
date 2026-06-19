function Get-ImperionCloudResource {
    <#
    .SYNOPSIS
        Collect a client tenant's Azure ARM cloud resources (subscriptions, resource groups,
        resources) and flatten them to bronze rows for the CMDB cloud-asset CI source.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the per-client Azure ARM cloud-resource
        inventory — slice 1 of epic #201 (ADR-0023). This is the CMDB cloud-asset feed,
        DISTINCT from Get-ImperionAzureResource: that collector lands the PARTNER-tenant,
        posture-scoped azure_resources set (ADR-0008 / migration 0038); THIS collector is
        per-managed-CLIENT (auth fans out per consented client tenant, §3 / ADR-0018) and
        shapes the rows for the CMDB cloud-asset CI (account-relatable), landing the NEW
        cloud_* bronze set. Source key 'azure_arm' (not 'azure') so the CMDB source is
        unambiguous downstream.

        Mints a cert-SP ARM token (Reader — already held, NO new grant) in the target tenant,
        pages /subscriptions, then per subscription /resourcegroups and /resources, and
        flattens each to the standard flat-table envelope. Emits three row kinds, each stamped
        with an `entity` discriminator that Set-ImperionCloudResourceToBronze routes on (and
        projects away — none of the bronze tables has an `entity` column):

          entity 'subscriptions'   -> cloud_subscriptions   (external_id = subscriptionId)
          entity 'resource_groups' -> cloud_resource_groups (external_id = the RG ARM id)
          entity 'resources'       -> cloud_resources       (external_id = the resource ARM id)

        Bronze over-collects: the full ARM object is lossless in raw_payload; the flat columns
        are the CMDB-queryable subset. Per-tenant isolation: every row carries the tenant
        authenticated against (no cross-tenant reads). Returns rows; does not write. Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Client tenant to authenticate against (the consented onboarding-app tenant, ADR-0018).
        Defaults to the partner tenant (dormant-safe: with no client tenants configured the
        task fans out over the partner tenant only).
    .PARAMETER ApiVersion
        ARM api-version for the subscription / resource-group / resource reads. Default 2022-09-01.
    .OUTPUTS
        Flat bronze rows (source 'azure_arm', entity-discriminated) for Set-ImperionCloudResourceToBronze.
    .EXAMPLE
        Get-ImperionCloudResource -TenantId $clientTenant | Set-ImperionCloudResourceToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $ApiVersion = '2022-09-01'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionArmToken -TenantId $TenantId
    $subscriptions = Invoke-ImperionArmRequest -Path '/subscriptions?api-version=2022-12-01' -AccessToken $token

    $rows = [System.Collections.Generic.List[object]]::new()
    $subscriptionCount = 0
    $resourceGroupCount = 0
    $resourceCount = 0
    $rgFromId = { param($id) if ($id -match '/resourceGroups/([^/]+)') { $Matches[1] } }

    foreach ($subscription in $subscriptions) {
        $subscriptionCount++
        $subscriptionId = Get-ImperionMember $subscription 'subscriptionId'

        $subscription | ConvertTo-ImperionFlatObject -Source 'azure_arm' -TenantId $TenantId `
            -ExternalIdProperty 'subscriptionId' -PropertyMap ([ordered]@{
                entity        = { 'subscriptions' }
                display_name  = 'displayName'
                state         = 'state'
                sub_tenant_id = 'tenantId'
            }) | ForEach-Object { $rows.Add($_) }

        $resourceGroups = Invoke-ImperionArmRequest -AccessToken $token `
            -Path "/subscriptions/$subscriptionId/resourcegroups?api-version=$ApiVersion"
        foreach ($resourceGroup in $resourceGroups) {
            $resourceGroupCount++
            $resourceGroup | ConvertTo-ImperionFlatObject -Source 'azure_arm' -TenantId $TenantId `
                -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
                    entity            = { 'resource_groups' }
                    name              = 'name'
                    location          = 'location'
                    subscription_id   = { $subscriptionId }
                    provisioning_state = 'properties.provisioningState'
                    tags              = { param($x) ConvertTo-ImperionTagJson (Get-ImperionMember $x 'tags') }
                }) | ForEach-Object { $rows.Add($_) }
        }

        $resources = Invoke-ImperionArmRequest -AccessToken $token `
            -Path "/subscriptions/$subscriptionId/resources?api-version=$ApiVersion"
        foreach ($resource in $resources) {
            $resourceCount++
            $resource | ConvertTo-ImperionFlatObject -Source 'azure_arm' -TenantId $TenantId `
                -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
                    entity          = { 'resources' }
                    name            = 'name'
                    type            = 'type'
                    location        = 'location'
                    kind            = 'kind'
                    sku             = 'sku.name'
                    resource_group  = { param($x) & $rgFromId (Get-ImperionMember $x 'id') }
                    subscription_id = { $subscriptionId }
                    tags            = { param($x) ConvertTo-ImperionTagJson (Get-ImperionMember $x 'tags') }
                }) | ForEach-Object { $rows.Add($_) }
        }
    }

    Write-ImperionLog -Source 'azure_arm' -Message 'Azure ARM cloud resources collected.' -Data @{
        tenant = $TenantId; subscriptions = $subscriptionCount; resource_groups = $resourceGroupCount
        resources = $resourceCount; rows = $rows.Count
    }
    return $rows.ToArray()
}
