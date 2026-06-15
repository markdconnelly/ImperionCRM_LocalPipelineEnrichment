function Get-ImperionEntraAppRegistration {
    <#
    .SYNOPSIS
        Collect a tenant's Entra application registrations and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for tenant-hygiene app registrations (issue #142;
        front-end schema issue #260, table entra_app_registrations). Mints a Graph token for
        the tenant (GDAP for customer tenants), pages /applications — application permission
        Application.Read.All, read-only — and flattens each app to the standard flat-table
        envelope, source 'm365', external_id = the application object id.

        Distinct from service principals (Invoke-ImperionAzureInventorySync /
        m365_service_principals): an application registration is the app *definition* in its
        home tenant; the service principal is the per-tenant instance. The hygiene gap this
        closes is the credential picture on the registration itself — counts and the nearest
        expiry of passwordCredentials (client secrets) and keyCredentials (certs), so a
        benchmark can flag expiring/expired or secret-bearing apps. The same nearest-expiry
        reduction the service-principal collector uses is reused here.

        Collections (identifierUris, tags) join to delimited text and booleans land as
        'true'/'false' via the standard scalar coercion (bronze flat columns are all-text;
        lossless types — the full credential arrays, required resource access, etc. — live
        in raw_payload).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionEntraAppRegistrationToBronze.
    .EXAMPLE
        Get-ImperionEntraAppRegistration | Set-ImperionEntraAppRegistrationToBronze
    .EXAMPLE
        Get-ImperionEntraAppRegistration -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $applications = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/applications' -AccessToken $token

    # Nearest future-or-past credential expiry across an array of {endDateTime} credentials —
    # the hygiene signal a benchmark reads (mirrors Invoke-ImperionServicePrincipalSync).
    $nearestExpiry = {
        param($expiryCandidates)
        if (-not $expiryCandidates) { return $null }
        ($expiryCandidates | Where-Object { $_.endDateTime } | Sort-Object endDateTime | Select-Object -First 1).endDateTime
    }

    # Schema issue #260 flat columns (entra_app_registrations); collections/booleans coerced
    # by ConvertTo-ImperionFlatObject. external_id = id (the application object id).
    $map = [ordered]@{
        app_id                     = 'appId'
        display_name               = 'displayName'
        sign_in_audience           = 'signInAudience'
        publisher_domain           = 'publisherDomain'
        verified_publisher         = 'verifiedPublisher.displayName'
        identifier_uris            = { param($a) (Get-ImperionMember $a 'identifierUris') | Join-ImperionValues }
        tags                       = { param($a) (Get-ImperionMember $a 'tags') | Join-ImperionValues }
        required_resource_access_count = { param($a) (Get-ImperionMember $a 'requiredResourceAccess' | Measure-Object).Count }
        key_credentials_count      = { param($a) (Get-ImperionMember $a 'keyCredentials' | Measure-Object).Count }
        key_credential_next_expiry = { param($a) & $nearestExpiry (Get-ImperionMember $a 'keyCredentials') }
        pwd_credentials_count      = { param($a) (Get-ImperionMember $a 'passwordCredentials' | Measure-Object).Count }
        pwd_credential_next_expiry = { param($a) & $nearestExpiry (Get-ImperionMember $a 'passwordCredentials') }
        created_date_time          = 'createdDateTime'
    }

    $rows = @($applications | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra app registrations collected.' -Data @{
        tenant = $TenantId; applications = @($applications).Count; rows = $rows.Count
    }
    return $rows
}
