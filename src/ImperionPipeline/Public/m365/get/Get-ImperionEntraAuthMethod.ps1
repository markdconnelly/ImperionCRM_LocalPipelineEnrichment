function Get-ImperionEntraAuthMethod {
    <#
    .SYNOPSIS
        Collect per-user MFA registration state (Entra auth methods report) and flatten it to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the per-user authentication-method /
        MFA-registration feed (issue #140; front-end migration 0077 / ADR-0051 posture
        model). Pages Graph /reports/authenticationMethods/userRegistrationDetails —
        ONE call per tenant covers every user's isMfaRegistered / isMfaCapable /
        methodsRegistered / preferred-method state (application permission
        UserAuthenticationMethod.Read.All, already admin-consented) — and flattens each
        record to the standard flat-table envelope, source 'm365' (the
        entra_conditional_access_policies convention), external_id = the Entra user
        object id (the report's id).

        Collections (methodsRegistered, systemPreferredAuthenticationMethods) join to
        delimited text via the standard scalar coercion; booleans land as 'true'/'false'
        (bronze flat columns are all-text; lossless types live in raw_payload).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionEntraAuthMethodToBronze.
    .EXAMPLE
        Get-ImperionEntraAuthMethod | Set-ImperionEntraAuthMethodToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $registrationDetails = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails' `
        -AccessToken $token

    # Migration-0077 flat columns; collections/booleans coerced by ConvertTo-ImperionFlatObject.
    $map = [ordered]@{
        user_principal_name = 'userPrincipalName'
        user_display_name   = 'userDisplayName'
        user_type           = 'userType'
        is_admin            = 'isAdmin'
        is_mfa_capable      = 'isMfaCapable'
        is_mfa_registered   = 'isMfaRegistered'
        is_passwordless_capable = 'isPasswordlessCapable'
        is_sspr_capable     = 'isSsprCapable'
        is_sspr_enabled     = 'isSsprEnabled'
        is_sspr_registered  = 'isSsprRegistered'
        is_system_preferred_authentication_method_enabled = 'isSystemPreferredAuthenticationMethodEnabled'
        system_preferred_authentication_methods           = 'systemPreferredAuthenticationMethods'
        methods_registered  = 'methodsRegistered'
        user_preferred_method_for_secondary_authentication = 'userPreferredMethodForSecondaryAuthentication'
        last_updated_date_time = 'lastUpdatedDateTime'
    }

    $rows = @($registrationDetails | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra auth-method registration details collected.' -Data @{
        users = @($registrationDetails).Count; rows = $rows.Count
    }
    return $rows
}
