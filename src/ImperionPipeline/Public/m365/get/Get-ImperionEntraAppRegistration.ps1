function Get-ImperionEntraAppRegistration {
    <#
    .SYNOPSIS
        Collect a tenant's Entra application registrations and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for tenant-hygiene app registrations (issue #219/#142;
        front-end migration 0136 / #260, table entra_app_registrations). Mints a Graph token for
        the tenant (client tenants via the per-client onboarding app, §3), pages /applications —
        application permission Application.Read.All, read-only — and flattens each app to the
        standard flat-table envelope, source 'm365', external_id = the application object id.

        Distinct from service principals (Invoke-ImperionAzureInventorySync /
        m365_service_principals): an application registration is the app *definition* in its
        home tenant; the service principal is the per-tenant instance. The hygiene gap this
        closes is the credential picture on the registration itself — the rotation signals
        migration 0136 reads: key_credential_count + password_credential_count, the single
        earliest_credential_expiry across BOTH key (cert) and password (secret) credentials,
        and has_expired_credential (any credential already past expiry).

        Flat columns are EXACTLY the migration-0136 entra_app_registrations set. Everything
        else (verified publisher, identifier URIs, tags, required-resource-access, the full
        credential arrays, …) stays lossless in raw_payload (bronze over-collects the full
        payload; the flat columns are the 0136 filter). Booleans land as 'true'/'false' via
        the standard scalar coercion.

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Client tenants resolve via the
        per-client onboarding app (§3).
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
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $applications = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/applications' -AccessToken $token

    # Credential expiries across BOTH key (cert) and password (secret) credentials, parsed
    # and sorted ascending — the basis for the 0136 rotation signals (earliest_credential_expiry
    # / has_expired_credential). Returns objects { Raw (source string); At (offset) }.
    $credentialExpiries = {
        param($app)
        $parsed = foreach ($credentialSet in @('keyCredentials', 'passwordCredentials')) {
            foreach ($credential in (Get-ImperionMember $app $credentialSet)) {
                $endDateTime = Get-ImperionMember $credential 'endDateTime'
                if ($endDateTime) {
                    $offset = [datetimeoffset]::MinValue
                    if ([datetimeoffset]::TryParse([string]$endDateTime, [ref]$offset)) {
                        [pscustomobject]@{ Raw = [string]$endDateTime; At = $offset }
                    }
                }
            }
        }
        @($parsed | Sort-Object At)
    }

    # Migration 0136 flat columns (entra_app_registrations); booleans coerced by
    # ConvertTo-ImperionFlatObject. external_id = id (the application object id).
    $map = [ordered]@{
        app_id                     = 'appId'
        display_name               = 'displayName'
        sign_in_audience           = 'signInAudience'
        publisher_domain           = 'publisherDomain'
        created_date_time          = 'createdDateTime'
        key_credential_count       = { param($a) (Get-ImperionMember $a 'keyCredentials' | Measure-Object).Count }
        password_credential_count  = { param($a) (Get-ImperionMember $a 'passwordCredentials' | Measure-Object).Count }
        # @(… | Where-Object) re-arrays the result ('&' collapses an empty/single return to a
        # scalar, and .Count on that throws under StrictMode); nulls are filtered out.
        earliest_credential_expiry = { param($a) $expiries = @(& $credentialExpiries $a | Where-Object { $_ }); if ($expiries.Count) { $expiries[0].Raw } else { $null } }
        has_expired_credential     = { param($a) $expiries = @(& $credentialExpiries $a | Where-Object { $_ }); [bool]($expiries.Count -and $expiries[0].At -lt [datetimeoffset]::UtcNow) }
    }

    $rows = @($applications | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra app registrations collected.' -Data @{
        tenant = $TenantId; applications = @($applications).Count; rows = $rows.Count
    }
    return $rows
}
