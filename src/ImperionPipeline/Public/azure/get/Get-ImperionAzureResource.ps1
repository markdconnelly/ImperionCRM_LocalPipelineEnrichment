function Get-ImperionAzureResource {
    <#
    .SYNOPSIS
        Collect a subscription's Azure resources and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): ARM token (Reader), pages
        /subscriptions/{id}/resources, flattens to the standard flat-table envelope (tags
        collapsed; resource group parsed from the resource id). Returns rows; does not write.
        Requires Initialize-ImperionContext.
    .PARAMETER SubscriptionId
        The subscription to enumerate (from Get-ImperionAzureSubscription).
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .PARAMETER ApiVersion
        ARM api-version for resource listing. Default 2022-09-01.
    .EXAMPLE
        Get-ImperionAzureResource -SubscriptionId $sub
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
    $resources = Invoke-ImperionArmRequest -Path "/subscriptions/$SubscriptionId/resources?api-version=$ApiVersion" -AccessToken $token

    $map = [ordered]@{
        name            = 'name'
        type            = 'type'
        location        = 'location'
        kind            = 'kind'
        sku             = 'sku.name'
        resource_group  = { param($x) $id = Get-ImperionMember $x 'id'; if ($id -match '/resourceGroups/([^/]+)') { $Matches[1] } }
        subscription_id = { $SubscriptionId }
        tags            = { param($x) ConvertTo-ImperionTagString (Get-ImperionMember $x 'tags') }
    }

    $resources | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'azure' -TenantId $TenantId -ExternalIdProperty 'id'
}
