function Invoke-ImperionPax8Request {
    <#
    .SYNOPSIS
        GET a Pax8 API collection, exchanging the OAuth2 client-credentials pair for a bearer first.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the Pax8 REST API v1 (issue #279,
        epic #1042). Pax8 authenticates with an OAuth2 **client-credentials** grant: a
        client_id + client_secret (the MSP's single distributor-account app credential, an
        Auth0 token endpoint) is exchanged for a short-lived BEARER, which then rides every
        read. This helper owns that exchange and the page-walk so the get layer never touches
        the token directly (the Datto RMM / KQM idiom).

        AUTH EXCHANGE: POST {TokenUri} with a JSON body
        `{ client_id, client_secret, audience, grant_type=client_credentials }` yields
        `{ access_token, expires_in, ... }`. The bearer is held ONLY in memory for this call
        and is NEVER logged (the retry core redacts bearer headers + token-exchange bodies).
        The client_secret never rides a querystring.

        PAGING: Pax8 v1 returns Spring-style pages —
        `{ content: [ ... ], page: { size, totalElements, totalPages, number } }`. This helper
        walks `page=0,1,…` with a fixed `size` until the last page (`number + 1 >= totalPages`),
        hard-capped by -MaxPages. A bare-array body is tolerated (StrictMode-safe), pending
        live-shape verification.

        CONFIRM BEFORE LIVE USE: the token endpoint host/path, the `audience` value
        (`api://p8p.client` per the documented Pax8 bootstrap), the API origin
        (`https://api.pax8.com`), and the page wrapper property names are modeled from the
        published Pax8 API docs but UNVERIFIED against the real account until the credential
        lands (the KQM/Datto precedent) — confirm on the first real pull.
    .PARAMETER ClientId
        Pax8 OAuth2 client id (the MSP distributor-account app). Not secret, but resolved from
        the same custody as the secret.
    .PARAMETER ClientSecret
        Pax8 OAuth2 client secret, exchanged for a bearer. Held only in memory; never logged.
    .PARAMETER Path
        Resource path under the API origin, e.g. '/v1/companies'.
    .PARAMETER BaseUri
        Pax8 API origin. Default 'https://api.pax8.com'.
    .PARAMETER TokenUri
        Pax8 OAuth2 token endpoint. Default 'https://login.pax8.com/oauth/token'.
    .PARAMETER Audience
        OAuth2 audience claim for the token request. Default 'api://p8p.client' (documented).
    .PARAMETER ItemsProperty
        Dotted path to the rows in the page body. Default 'content'. A bare array body is
        tolerated when this is absent.
    .PARAMETER PageSize
        Rows requested per page (querystring `size`). Default 200.
    .PARAMETER MaxPages
        Safety cap on pages per call (runaway guard). Default 200.
    .EXAMPLE
        Invoke-ImperionPax8Request -ClientId $id -ClientSecret $secret -Path '/v1/companies'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ClientId,
        [Parameter(Mandatory)][string] $ClientSecret,
        [Parameter(Mandatory)][string] $Path,
        [string] $BaseUri = 'https://api.pax8.com',
        [string] $TokenUri = 'https://login.pax8.com/oauth/token',
        [string] $Audience = 'api://p8p.client',
        [string] $ItemsProperty = 'content',
        [ValidateRange(1, 500)][int] $PageSize = 200,
        [ValidateRange(1, 1000)][int] $MaxPages = 200
    )

    # Exchange the client-credentials pair for a short-lived bearer. The body carries the
    # secret; the retry core redacts it from logs. (grant/audience modeled from the docs.)
    $tokenBody = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        audience      = $Audience
        grant_type    = 'client_credentials'
    } | ConvertTo-Json -Compress
    $tokenResponse = Invoke-ImperionRestWithRetry -Uri $TokenUri -Method POST `
        -Headers @{ Accept = 'application/json' } -Body $tokenBody -ContentType 'application/json'
    $accessToken = Get-ImperionPropertyPath -InputObject $tokenResponse.Body -Path 'access_token'
    if (-not $accessToken) {
        throw 'Pax8 token exchange returned no access_token (issue #279) — verify the client-credentials grant against the live account.'
    }

    $headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()
    $separator = if ($Path.Contains('?')) { '&' } else { '?' }

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $uri = '{0}{1}{2}page={3}&size={4}' -f $BaseUri.TrimEnd('/'), $Path, $separator, $page, $PageSize
        $resp = Invoke-ImperionRestWithRetry -Uri $uri -Headers $headers -Method GET

        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        $pageItems = @(if ($null -ne $collection) { $collection } elseif ($null -ne $resp.Body) { $resp.Body })
        foreach ($item in $pageItems) { $items.Add($item) }

        # Stop on the last Spring page (number + 1 >= totalPages). When the wrapper is absent
        # (bare array / single page), a short page ends the loop (StrictMode-safe).
        $totalPages = Get-ImperionPropertyPath -InputObject $resp.Body -Path 'page.totalPages'
        if ($null -ne $totalPages) {
            if (($page + 1) -ge [int]$totalPages) { break }
        }
        elseif ($pageItems.Count -lt $PageSize) {
            break
        }
    }
    return $items.ToArray()
}
