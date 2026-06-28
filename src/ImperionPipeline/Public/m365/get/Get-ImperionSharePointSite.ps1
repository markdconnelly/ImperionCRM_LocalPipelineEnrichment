function Get-ImperionSharePointSite {
    <#
    .SYNOPSIS
        Collect the SharePoint site inventory (Graph /sites/getAllSites) and flatten it to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the SharePoint site inventory (issue #137;
        front-end migration 0078 / issue #255). Pages Graph /sites/getAllSites — the
        application-permission enumeration of every site in the tenant, personal
        (OneDrive) sites included and flagged via isPersonalSite (application permission
        Sites.Read.All, already admin-consented) — and flattens each site to the standard
        flat-table envelope, source 'm365' (the entra_auth_methods convention),
        external_id = the Graph composite site id (hostname,siteCollectionId,webId).

        SITE METADATA ONLY (Mark's 2026-06-12 per-source verdict): this collector makes
        NO calls to /drives, /drive, /items, or any file/content endpoint —
        Files.Read.All is pruned from the Onboarding app and migration 0078 carries no
        file/drive/item columns. Storage metrics map only where Graph exposes them on
        the site object itself (nullable; today they are typically absent on
        getAllSites — they stay NULL, never fetched from a drive).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionSharePointSiteToBronze.
    .EXAMPLE
        Get-ImperionSharePointSite | Set-ImperionSharePointSiteToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $sites = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/sites/getAllSites' `
        -AccessToken $token

    # Migration-0078 flat columns; booleans/dates coerced by ConvertTo-ImperionFlatObject.
    # Storage metrics are nullable — mapped only if Graph exposes them on the site object.
    $map = [ordered]@{
        display_name             = 'displayName'
        name                     = 'name'
        web_url                  = 'webUrl'
        description              = 'description'
        created_date_time        = 'createdDateTime'
        last_modified_date_time  = 'lastModifiedDateTime'
        web_template             = 'webTemplate'
        is_personal_site         = 'isPersonalSite'
        site_collection_hostname = 'siteCollection.hostname'
        storage_used_bytes       = 'storageUsedInBytes'
        storage_quota_bytes      = 'storageQuotaInBytes'
    }

    $rows = @($sites | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'SharePoint site inventory collected.' -Data @{
        sites = @($sites).Count; rows = $rows.Count
    }
    return $rows
}
