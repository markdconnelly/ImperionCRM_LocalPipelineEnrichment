function Get-ImperionAccessToken {
    <#
    .SYNOPSIS
        Acquire an app-only access token via the certificate-backed Entra app (ADR-0002).
    .DESCRIPTION
        Uses MSAL.PS with the machine certificate (client-credential cert auth) to mint a
        short-lived token for a given resource and tenant. Tokens are cached per
        (tenant, resource) until shortly before expiry. Resources:
          Graph    https://graph.microsoft.com/.default
          ARM      https://management.azure.com/.default
          Postgres https://ossrdbms-aad.database.windows.net/.default
        For customer tenants, pass that tenant's id (GDAP) — the cert app must hold the
        delegated relationship (CLAUDE.md §3).
    .PARAMETER Resource
        The .default scope / resource for the token.
    .PARAMETER TenantId
        Tenant to authenticate against (partner tenant by default).
    .PARAMETER ClientId
        The Entra app (client) id.
    .PARAMETER CertThumbprint
        Thumbprint of the certificate (certificate auth — the preferred default). Looked up
        in Cert:\LocalMachine\My first (the unattended end-state, ADR-0002), falling back to
        Cert:\CurrentUser\My (interim interactive runs before the service identity owns a
        machine-store cert).
    .PARAMETER ClientSecret
        The enterprise-app client secret (secret auth — the alternative to a certificate,
        frontend ADR-0103). A SecureString; the caller resolves it from the SecretStore and
        it is never logged or written to disk. Use this OR -CertThumbprint, never both.
    .EXAMPLE
        $tok = Get-ImperionAccessToken -Resource 'https://graph.microsoft.com/.default' -TenantId $tid -ClientId $cid -CertThumbprint $thumb
    .EXAMPLE
        $tok = Get-ImperionAccessToken -Resource 'https://management.azure.com/.default' -TenantId $tid -ClientId $cid -ClientSecret $secret
    #>
    [CmdletBinding(DefaultParameterSetName = 'Certificate')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Resource,
        [Parameter(Mandatory)][string] $TenantId,
        [Parameter(Mandatory)][string] $ClientId,
        [Parameter(Mandatory, ParameterSetName = 'Certificate')][string] $CertThumbprint,
        [Parameter(Mandatory, ParameterSetName = 'Secret')][securestring] $ClientSecret
    )

    if (-not $script:ImperionTokenCache) { $script:ImperionTokenCache = @{} }
    $cacheKey = "$TenantId|$Resource"
    $cached = $script:ImperionTokenCache[$cacheKey]
    if ($cached -and $cached.ExpiresOn -gt (Get-Date).AddMinutes(5)) {
        return $cached.AccessToken
    }

    if ($PSCmdlet.ParameterSetName -eq 'Secret') {
        # Secret auth (ADR-0103): client-credentials with the enterprise-app secret. The
        # SecureString goes straight to MSAL — never converted to plaintext or logged.
        $result = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret -Scopes $Resource -ErrorAction Stop
    }
    else {
        # Certificate auth (default). Machine store first (unattended end-state); user store as the interim fallback.
        $cert = Get-Item -Path ("Cert:\LocalMachine\My\{0}" -f $CertThumbprint) -ErrorAction SilentlyContinue
        if (-not $cert) {
            $cert = Get-Item -Path ("Cert:\CurrentUser\My\{0}" -f $CertThumbprint) -ErrorAction SilentlyContinue
        }
        if (-not $cert) {
            throw "Certificate $CertThumbprint not found in Cert:\LocalMachine\My or Cert:\CurrentUser\My."
        }
        if (-not $cert.HasPrivateKey) {
            throw "Certificate $CertThumbprint has no accessible private key for this identity."
        }
        $result = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -ClientCertificate $cert -Scopes $Resource -ErrorAction Stop
    }

    $script:ImperionTokenCache[$cacheKey] = [pscustomobject]@{
        AccessToken = $result.AccessToken
        ExpiresOn   = $result.ExpiresOn.LocalDateTime
    }
    return $result.AccessToken
}
