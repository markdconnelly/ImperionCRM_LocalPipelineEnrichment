function Get-ImperionAzureResourceGroup {
    <#
    .SYNOPSIS
        Collect a subscription's Azure resource groups and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): ARM token (Reader), pages
        /subscriptions/{id}/resourcegroups, flattens to the standard flat-table envelope (tags
        collapsed to k=v; k=v). Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER SubscriptionId
        The subscription to enumerate (from Get-ImperionAzureSubscription).
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .PARAMETER ApiVersion
        ARM api-version for resource-group listing. Default 2022-09-01.
    .EXAMPLE
        Get-ImperionAzureResourceGroup -SubscriptionId $sub
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $SubscriptionId,
        [string] $TenantId,
        [string] $ApiVersion = '2022-09-01'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionArmToken -TenantId $TenantId
    $groups = Invoke-ImperionArmRequest -Path "/subscriptions/$SubscriptionId/resourcegroups?api-version=$ApiVersion" -AccessToken $token

    $map = [ordered]@{
        name               = 'name'
        location           = 'location'
        provisioning_state = 'properties.provisioningState'
        managed_by         = 'managedBy'
        subscription_id    = { $SubscriptionId }
        tags               = { param($x) ConvertTo-ImperionTagString (Get-ImperionMember $x 'tags') }
    }

    $groups | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'azure' -TenantId $TenantId -ExternalIdProperty 'id'
}
