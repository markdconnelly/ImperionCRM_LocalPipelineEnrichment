function Get-ImperionAzureSubscription {
    <#
    .SYNOPSIS
        Collect Azure subscriptions and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): mints an ARM token (Reader), pages /subscriptions, and
        flattens each to the standard flat-table envelope. Returns rows; does not write. Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .EXAMPLE
        Get-ImperionAzureSubscription
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionArmToken -TenantId $TenantId
    $subscriptions = Invoke-ImperionArmRequest -Path '/subscriptions?api-version=2022-12-01' -AccessToken $token

    $map = [ordered]@{
        display_name         = 'displayName'
        state                = 'state'
        sub_tenant_id        = 'tenantId'
        authorization_source = 'authorizationSource'
        quota_id             = 'subscriptionPolicies.quotaId'
        spending_limit       = 'subscriptionPolicies.spendingLimit'
    }

    $subscriptions | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'azure' -TenantId $TenantId -ExternalIdProperty 'subscriptionId'
}
