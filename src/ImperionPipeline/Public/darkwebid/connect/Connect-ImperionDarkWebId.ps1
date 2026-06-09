function Connect-ImperionDarkWebId {
    <#
    .SYNOPSIS
        Acquire a Dark Web ID (ID Agent) API access token via OAuth2 client-credentials.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4). POSTs a client-credentials grant to the
        token endpoint and returns a short-lived bearer token, cached per (ClientId, endpoint)
        until shortly before expiry. Pure: the client id/secret are passed in (resolved from
        the SecretStore by the caller), so the function holds no stored secret and is mockable.

        CONFIRM BEFORE LIVE USE: the Dark Web ID token endpoint URL (and whether a scope is
        required) must be verified against the current ID Agent / Dark Web ID Partner API
        documentation — it is a required parameter here precisely so nothing is fabricated.
    .PARAMETER ClientId
        OAuth client id for the Dark Web ID API integration.
    .PARAMETER ClientSecret
        OAuth client secret (passed in from the SecretStore; never stored by this module).
    .PARAMETER TokenEndpoint
        The OAuth2 token endpoint URL (confirm against vendor docs).
    .PARAMETER Scope
        Optional OAuth scope, if the API requires one.
    .PARAMETER Force
        Bypass the cache and request a fresh token.
    .EXAMPLE
        $tok = Connect-ImperionDarkWebId -ClientId $id -ClientSecret $secret -TokenEndpoint $url
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $ClientId,
        [Parameter(Mandatory)][string] $ClientSecret,
        [Parameter(Mandatory)][string] $TokenEndpoint,
        [string] $Scope,
        [switch] $Force
    )

    if (-not $script:ImperionDarkWebIdTokenCache) { $script:ImperionDarkWebIdTokenCache = @{} }
    $cacheKey = "$ClientId|$TokenEndpoint"
    $cached = $script:ImperionDarkWebIdTokenCache[$cacheKey]
    if (-not $Force -and $cached -and $cached.ExpiresOn -gt (Get-Date).AddMinutes(1)) {
        return $cached.AccessToken
    }

    $form = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
    }
    if ($Scope) { $form['scope'] = $Scope }

    $resp = Invoke-ImperionRestWithRetry -Uri $TokenEndpoint -Method POST -Body $form `
        -ContentType 'application/x-www-form-urlencoded' -Headers @{ Accept = 'application/json' }

    $accessToken = if ($resp.Body -and $resp.Body.PSObject.Properties['access_token']) { $resp.Body.access_token } else { $null }
    if (-not $accessToken) {
        throw 'Dark Web ID token endpoint returned no access_token.'
    }
    $expiresIn = if ($resp.Body.PSObject.Properties['expires_in']) { [int]$resp.Body.expires_in } else { 3600 }
    $script:ImperionDarkWebIdTokenCache[$cacheKey] = [pscustomobject]@{
        AccessToken = $accessToken
        ExpiresOn   = (Get-Date).AddSeconds($expiresIn)
    }
    return $accessToken
}
