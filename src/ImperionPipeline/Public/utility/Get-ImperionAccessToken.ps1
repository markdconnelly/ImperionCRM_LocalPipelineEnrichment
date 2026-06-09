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
        Thumbprint of the certificate. Looked up in Cert:\LocalMachine\My first (the
        unattended end-state, ADR-0002), falling back to Cert:\CurrentUser\My (interim
        interactive runs before the service identity owns a machine-store cert).
    .EXAMPLE
        $tok = Get-ImperionAccessToken -Resource 'https://graph.microsoft.com/.default' -TenantId $tid -ClientId $cid -CertThumbprint $thumb
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Resource,
        [Parameter(Mandatory)][string] $TenantId,
        [Parameter(Mandatory)][string] $ClientId,
        [Parameter(Mandatory)][string] $CertThumbprint
    )

    if (-not $script:ImperionTokenCache) { $script:ImperionTokenCache = @{} }
    $cacheKey = "$TenantId|$Resource"
    $cached = $script:ImperionTokenCache[$cacheKey]
    if ($cached -and $cached.ExpiresOn -gt (Get-Date).AddMinutes(5)) {
        return $cached.AccessToken
    }

    # Machine store first (unattended end-state); user store as the interim fallback.
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
    $script:ImperionTokenCache[$cacheKey] = [pscustomobject]@{
        AccessToken = $result.AccessToken
        ExpiresOn   = $result.ExpiresOn.LocalDateTime
    }
    return $result.AccessToken
}
