function Get-ImperionIntuneManagedApp {
    <#
    .SYNOPSIS
        Collect the Intune managed-app inventory for a tenant and flatten it to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Intune managed-app feed (issue #143;
        front-end migration pending, ImperionCRM #261). Mints a Graph token for the tenant
        (GDAP for customer tenants, §3), pages
        /deviceAppManagement/mobileApps (the deviceAppManagement managed-app inventory:
        store apps, LOB apps, web links, the full app estate Intune manages), and flattens
        each to the standard flat-table envelope (target bronze intune_managed_apps),
        source 'm365', external_id = the Graph app id.

        This completes the drillable Intune asset detail (Mark per-source review
        2026-06-12): devices (Get-ImperionM365Device), compliance + configuration
        (front-end 0069/0038, ADR-0047/0051) already exist — managed apps were the
        remaining gap. The flat columns carry the publishing/assignment-grade fields
        (publishing state, featured flag, publisher, version, owner) for the asset page;
        the full per-app payload (including the @odata.type discriminating store vs LOB vs
        web app, and any type-specific fields) stays lossless in raw_payload for silver to
        refine.

        `app_type` flattens the Graph `@odata.type` so the device/asset drill-in can group
        by app archetype without re-parsing the payload. `largeIcon` (a base64 blob) is
        deliberately NOT lifted to a flat column — it bloats every row and adds no query
        value; it survives in raw_payload if ever needed.

        Returns rows; does not write. Requires Initialize-ImperionContext and the
        application permission DeviceManagementApps.Read.All.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
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
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $managedApps = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps' `
        -AccessToken $token

    # Proposed intune_managed_apps flat columns (front-end migration pending, ImperionCRM
    # #261). Booleans/dates coerced to text by ConvertTo-ImperionFlatObject; the full
    # payload (icon, type-specific fields) stays lossless in raw_payload.
    $map = [ordered]@{
        # @odata.type carries the app archetype (e.g. #microsoft.graph.win32LobApp,
        # #microsoft.graph.officeSuiteApp); trim the namespace to the bare type for the drill-in.
        # The literal property name contains a dot, so read it directly rather than via the
        # dotted-path helper (which would split '@odata.type' into two hops).
        app_type            = { param($a)
            $odataProperty = $a.PSObject.Properties['@odata.type']
            if ($odataProperty -and $odataProperty.Value) {
                ([string]$odataProperty.Value) -replace '^#microsoft\.graph\.', ''
            }
            else { $null }
        }
        display_name        = 'displayName'
        description         = 'description'
        publisher           = 'publisher'
        publishing_state    = 'publishingState'
        is_featured         = 'isFeatured'
        is_assigned         = 'isAssigned'
        version             = 'version'
        owner               = 'owner'
        developer           = 'developer'
        notes               = 'notes'
        information_url     = 'informationUrl'
        privacy_information_url = 'privacyInformationUrl'
        dependent_app_count = 'dependentAppCount'
        superseding_app_count = 'supersedingAppCount'
        superseded_app_count  = 'supersededAppCount'
        created_date_time   = 'createdDateTime'
        last_modified_date_time = 'lastModifiedDateTime'
    }

    $rows = @($managedApps | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Intune managed apps collected.' -Data @{
        apps = @($managedApps).Count; rows = $rows.Count
    }
    return $rows
}
