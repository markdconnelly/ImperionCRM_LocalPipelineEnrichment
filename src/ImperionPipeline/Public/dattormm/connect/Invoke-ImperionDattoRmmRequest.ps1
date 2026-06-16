function Invoke-ImperionDattoRmmRequest {
    <#
    .SYNOPSIS
        GET a Datto RMM API collection, exchanging the API key for a short-lived bearer first.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the Datto RMM REST API (issue #195,
        ADR-0018). Datto RMM authenticates with an API-KEY -> short-lived BEARER exchange against
        its `/auth/oauth/token` endpoint (OAuth2 client-credentials/password grant, key+secret
        as the basic-auth client), then carries the bearer on every read. This helper owns that
        exchange and the page-walk so the get layer never touches the token directly.

        AUTH EXCHANGE: POST {base}/auth/oauth/token (grant_type=password, the public OAuth2
        client `public-client`/`public`, the API key as username + the API key as password —
        Datto RMM's documented bootstrap) yields `{ access_token, expires_in, ... }`. The bearer
        is held ONLY in memory for this call and is NEVER logged (the retry core redacts bearer
        headers + token-exchange bodies, the KQM/QBO idiom). The API key never rides a querystring.

        PAGING: Datto RMM wraps list responses as
        `{ pageDetails: { count, nextPageUrl, prevPageUrl }, <entityProperty>: [ ... ] }`. This
        helper follows `pageDetails.nextPageUrl` until it is null, hard-capped by -MaxPages.

        CONFIRM BEFORE LIVE USE: the exact base host (per-platform, e.g.
        `https://<zone>-api.centrastage.net`), the token-exchange grant/params, the page wrapper
        property names, and the device entity property are modeled from the documented API but
        UNVERIFIED against the real account until the key lands (the KQM/EasyDMARC precedent) —
        tolerate a bare array body and confirm on the first real pull.
    .PARAMETER ApiKey
        Datto RMM API key, exchanged for a bearer. Held only in memory; never logged.
    .PARAMETER BaseUri
        Datto RMM API origin (per-platform). Default 'https://api.datto-rmm.com' (placeholder — confirm).
    .PARAMETER Path
        Resource path (without the origin), e.g. '/v2/account/devices'.
    .PARAMETER EntityProperty
        Property holding the rows in the page wrapper (e.g. 'devices'). When absent the body is
        tolerated as a bare array (StrictMode-safe), pending live-shape verification.
    .PARAMETER PageSize
        Rows requested per page (querystring `max`). Default 250.
    .PARAMETER MaxPages
        Safety cap on pages per call (runaway guard). Default 200.
    .EXAMPLE
        Invoke-ImperionDattoRmmRequest -ApiKey $key -Path '/v2/account/devices' -EntityProperty 'devices'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [string] $BaseUri = 'https://api.datto-rmm.com',
        [Parameter(Mandatory)][string] $Path,
        [string] $EntityProperty,
        [ValidateRange(1, 500)][int] $PageSize = 250,
        [ValidateRange(1, 500)][int] $MaxPages = 200
    )

    # Exchange the API key for a short-lived bearer. Body carries the secret; the retry core
    # redacts it from logs. (grant_type/client modeled from the documented bootstrap.)
    $tokenUri = '{0}/auth/oauth/token' -f $BaseUri.TrimEnd('/')
    $tokenBody = @{
        grant_type = 'password'
        username   = $ApiKey
        password   = $ApiKey
    }
    $tokenHeaders = @{
        Accept        = 'application/json'
        Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('public-client:public'))
    }
    $tokenResponse = Invoke-ImperionRestWithRetry -Uri $tokenUri -Headers $tokenHeaders -Method POST `
        -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
    $accessToken = Get-ImperionPropertyPath -InputObject $tokenResponse.Body -Path 'access_token'
    if (-not $accessToken) {
        throw 'Datto RMM token exchange returned no access_token (issue #195) — verify the bootstrap grant against the live account.'
    }

    $headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()

    $separator = if ($Path.Contains('?')) { '&' } else { '?' }
    $nextUri = '{0}{1}{2}max={3}' -f $BaseUri.TrimEnd('/'), $Path, $separator, $PageSize
    for ($page = 0; $page -lt $MaxPages; $page++) {
        $resp = Invoke-ImperionRestWithRetry -Uri $nextUri -Headers $headers -Method GET

        $collection = if ($EntityProperty) { Get-ImperionPropertyPath -InputObject $resp.Body -Path $EntityProperty }
        $pageItems = @(if ($null -ne $collection) { $collection } elseif ($null -ne $resp.Body) { $resp.Body })
        foreach ($item in $pageItems) { $items.Add($item) }

        # Follow the Datto RMM cursor; a null nextPageUrl ends the loop.
        $nextPageUrl = Get-ImperionPropertyPath -InputObject $resp.Body -Path 'pageDetails.nextPageUrl'
        if (-not $nextPageUrl) { break }
        $nextUri = [string]$nextPageUrl
    }
    return $items.ToArray()
}
