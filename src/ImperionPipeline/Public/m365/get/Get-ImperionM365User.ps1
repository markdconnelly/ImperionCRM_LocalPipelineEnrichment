function Get-ImperionM365User {
    <#
    .SYNOPSIS
        Collect Microsoft 365 (Entra) users for a tenant and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): mints a Graph token for the tenant (GDAP for customer
        tenants), pages /users with a trimmed $select, and flattens each to the standard
        flat-table envelope. Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
    .EXAMPLE
        Get-ImperionM365User -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $select = 'id,displayName,userPrincipalName,mail,jobTitle,department,companyName,accountEnabled,officeLocation,mobilePhone,businessPhones,userType,createdDateTime'
    $users = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/users' -AccessToken $token -Select $select

    $map = [ordered]@{
        display_name      = 'displayName'
        upn               = 'userPrincipalName'
        mail              = 'mail'
        job_title         = 'jobTitle'
        department        = 'department'
        company_name      = 'companyName'
        account_enabled   = 'accountEnabled'
        office_location   = 'officeLocation'
        mobile_phone      = 'mobilePhone'
        business_phones   = { param($u) (Get-ImperionMember $u 'businessPhones') | Join-ImperionValues }
        user_type         = 'userType'
        created_date_time = 'createdDateTime'
    }

    $users | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id'
}
