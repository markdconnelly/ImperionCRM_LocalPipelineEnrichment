function Get-ImperionEntraDomain {
    <#
    .SYNOPSIS
        Collect a tenant's Entra (Azure AD) domains and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for tenant-hygiene domains (issue #219/#142;
        front-end migration 0136 / #260, table entra_domains). Mints a Graph token for the
        tenant (client tenants via the per-client onboarding app, §3), pages /domains —
        application permission Domain.Read.All, read-only — and flattens each domain to the
        standard flat-table envelope, source 'm365' (the entra_* posture convention),
        external_id = the domain id (the domain name itself; Graph keys /domains on `id` = the FQDN).

        Flat columns are EXACTLY the migration-0136 entra_domains set so a benchmark can read
        the hygiene signals without parsing raw_payload: verification + authentication state,
        default/initial flags, and supported services. Collections (supportedServices) join to
        delimited text and booleans land as 'true'/'false' via the standard scalar coercion.
        Everything else (is_root, admin-managed, password-validity policy, …) stays lossless
        in raw_payload (bronze over-collects the full payload; the flat columns are the 0136 filter).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Client tenants resolve via the
        per-client onboarding app (§3).
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
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $domains = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/domains' -AccessToken $token

    # Migration 0136 flat columns (entra_domains); collections/booleans coerced by
    # ConvertTo-ImperionFlatObject. external_id = id (the domain FQDN, Graph's domain key).
    $map = [ordered]@{
        domain_name         = 'id'
        is_verified         = 'isVerified'
        is_default          = 'isDefault'
        is_initial          = 'isInitial'
        authentication_type = 'authenticationType'
        supported_services  = { param($d) (Get-ImperionMember $d 'supportedServices') | Join-ImperionValues }
    }

    $rows = @($domains | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra domains collected.' -Data @{
        tenant = $TenantId; domains = @($domains).Count; rows = $rows.Count
    }
    return $rows
}
