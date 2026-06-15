function Get-ImperionEntraDomain {
    <#
    .SYNOPSIS
        Collect a tenant's Entra (Azure AD) domains and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for tenant-hygiene domains (issue #142;
        front-end schema issue #260, table entra_domains). Mints a Graph token for the
        tenant (GDAP for customer tenants), pages /domains — application permission
        Domain.Read.All, read-only — and flattens each domain to the standard flat-table
        envelope, source 'm365' (the entra_* posture convention), external_id = the
        domain id (the domain name itself; Graph keys /domains on `id` = the FQDN).

        Hygiene-relevant fields surface here as flat text so a benchmark can read them
        without parsing raw_payload: verification + authentication state, default/initial
        flags, supported services, and admin-managed state. Collections
        (supportedServices) join to delimited text and booleans land as 'true'/'false'
        via the standard scalar coercion (bronze flat columns are all-text; lossless
        types live in raw_payload).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionEntraDomainToBronze.
    .EXAMPLE
        Get-ImperionEntraDomain | Set-ImperionEntraDomainToBronze
    .EXAMPLE
        Get-ImperionEntraDomain -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $domains = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/domains' -AccessToken $token

    # Schema issue #260 flat columns (entra_domains); collections/booleans coerced by
    # ConvertTo-ImperionFlatObject. external_id = id (the domain FQDN, Graph's domain key).
    $map = [ordered]@{
        domain_name                = 'id'
        authentication_type        = 'authenticationType'
        is_default                 = 'isDefault'
        is_initial                 = 'isInitial'
        is_root                    = 'isRoot'
        is_verified                = 'isVerified'
        is_admin_managed           = 'isAdminManaged'
        supported_services         = { param($d) (Get-ImperionMember $d 'supportedServices') | Join-ImperionValues }
        password_validity_period_in_days     = 'passwordValidityPeriodInDays'
        password_notification_window_in_days = 'passwordNotificationWindowInDays'
    }

    $rows = @($domains | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra domains collected.' -Data @{
        tenant = $TenantId; domains = @($domains).Count; rows = $rows.Count
    }
    return $rows
}
