function Get-ImperionAutotaskContact {
    <#
    .SYNOPSIS
        Collect Autotask contacts and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): pages the Contacts entity via the shared Autotask
        context (Get-ImperionAutotaskContext) and flattens each record to the standard
        flat-table envelope. Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER SinceDays
        Incremental window on lastActivityDate. Default 0 = full collection.
    .EXAMPLE
        Get-ImperionAutotaskContact -SinceDays 7
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

    $records = Invoke-ImperionAutotaskRequest -ApiBaseUrl $ctx.ApiBase -Headers $ctx.Headers -Entity 'Contacts' -Filter $filter

    $map = [ordered]@{
        company_id         = 'companyID'
        first_name         = 'firstName'
        last_name          = 'lastName'
        title              = 'title'
        email_address      = 'emailAddress'
        email_address2     = 'emailAddress2'
        phone              = 'phone'
        mobile_phone       = 'mobilePhone'
        alternate_phone    = 'alternatePhone'
        extension          = 'extension'
        address_line       = 'addressLine'
        address_line1      = 'addressLine1'
        city               = 'city'
        state              = 'state'
        zip_code           = 'zipCode'
        country_id         = 'countryID'
        primary_contact    = 'primaryContact'
        is_active          = 'isActive'
        last_activity_date = 'lastActivityDate'
        create_date        = 'createDate'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'autotask' -TenantId $TenantId -ExternalIdProperty 'id'
}
