function Get-ImperionAutotaskCompany {
    <#
    .SYNOPSIS
        Collect Autotask companies and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): resolves the Autotask credential from the SecretStore,
        discovers the zone, pages the Companies entity, and flattens each record to the standard
        flat-table envelope via ConvertTo-ImperionFlatObject. Returns rows; it does NOT write —
        the post layer (or a scheduled task) lands them into bronze. Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER SinceDays
        Incremental window on lastActivityDate. Default 0 = full collection.
    .EXAMPLE
        $rows = Get-ImperionAutotaskCompany
    .EXAMPLE
        Get-ImperionAutotaskCompany -SinceDays 7 | Format-Table company_name, is_active, last_activity_date
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [int] $SinceDays = 0
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $ctx = Get-ImperionAutotaskContext
    $filter = if ($SinceDays -gt 0) {
        @{ op = 'gte'; field = 'lastActivityDate'; value = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
    else { @{ op = 'gte'; field = 'id'; value = 0 } }

    $records = Invoke-ImperionAutotaskRequest -ApiBaseUrl $ctx.ApiBase -Headers $ctx.Headers -Entity 'Companies' -Filter $filter

    $map = [ordered]@{
        company_name       = 'companyName'
        company_number     = 'companyNumber'
        company_type       = 'companyType'
        classification     = 'classification'
        parent_company_id  = 'parentCompanyID'
        owner_resource_id  = 'ownerResourceID'
        phone              = 'phone'
        fax                = 'fax'
        web_address        = 'webAddress'
        address1           = 'address1'
        address2           = 'address2'
        city               = 'city'
        state              = 'state'
        postal_code        = 'postalCode'
        country_id         = 'countryID'
        territory_id       = 'territoryID'
        market_segment_id  = 'marketSegmentID'
        sic_code           = 'sicCode'
        stock_symbol       = 'stockSymbol'
        is_active          = 'isActive'
        is_tax_exempt      = 'isTaxExempt'
        last_activity_date = 'lastActivityDate'
        create_date        = 'createDate'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'autotask' -TenantId $TenantId -ExternalIdProperty 'id'
}
