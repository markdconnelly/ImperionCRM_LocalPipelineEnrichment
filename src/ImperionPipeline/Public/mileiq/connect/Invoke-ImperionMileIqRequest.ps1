function Invoke-ImperionMileIqRequest {
    <#
    .SYNOPSIS
        GET a MileIQ drives collection with OAuth2 bearer auth, following the API's paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the MileIQ read-only drives API
        (issue #167, ADR-0083 mileage capture). MileIQ is per-employee OAuth: the access token
        is passed in (the get layer resolves it per connected employee via
        Resolve-ImperionMileIqAccessToken), so this helper holds no secret and is
        mockable/StrictMode-safe. The token rides in an `Authorization: Bearer` header — never
        the querystring — so MileIQ request URLs are NOT secret-bearing.

        Read-only: only business-classified drives are requested (the caller passes the
        `?classification=business` filter; personal drives never enter the pipeline, ADR-0083).
        Paging walks `skip`/`take` windows and stops on a short page (fewer than -PageSize rows).
        -MaxPages caps a runaway loop. Throttling (429 + Retry-After) is handled by the shared
        retry core. The collection shape (bare array vs a wrapped `{ drives: [...] }` body) is
        tolerated both ways pending live verification against the real API.

        CONFIRM BEFORE LIVE USE (local-pipeline ADR for MileIQ; gated on the MileIQ External API
        credentials — markdconnelly/ImperionCRM#495 — and backend OAuth custody going live): the
        production base host, the exact drives path, the paging parameter names, and the
        response wrapper/property casing are modeled from the documented API but UNVERIFIED until
        the credentials land. See docs/integrations/mileiq.md.
    .PARAMETER AccessToken
        The per-employee MileIQ OAuth2 access token, sent as the bearer credential. Held only
        in memory; never logged.
    .PARAMETER Uri
        Full request URL (base + path + any filters, e.g.
        "https://api.mileiq.com/drives?classification=business&startDate=...").
    .PARAMETER PageSize
        Rows per page window (the `take` value); a page with fewer rows ends the loop.
    .PARAMETER MaxPages
        Safety cap on pages per call.
    .EXAMPLE
        Invoke-ImperionMileIqRequest -AccessToken $t -Uri 'https://api.mileiq.com/drives?classification=business'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $AccessToken,
        [Parameter(Mandatory)][string] $Uri,
        [ValidateRange(1, 500)][int] $PageSize = 200,
        [ValidateRange(1, 1000)][int] $MaxPages = 200
    )

    $headers = @{ Authorization = "Bearer $AccessToken"; Accept = 'application/json' }
    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    $items = [System.Collections.Generic.List[object]]::new()

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $skip = $page * $PageSize
        $pageUri = '{0}{1}skip={2}&take={3}' -f $Uri, $separator, $skip, $PageSize
        $resp = Invoke-ImperionRestWithRetry -Uri $pageUri -Headers $headers -Method GET

        # Tolerate both the documented wrapper ({ drives: [...] }) and, pending live
        # verification, a bare array body. The @(if) keeps $pageItems a real array even when
        # the page is empty (StrictMode-safe).
        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path 'drives'
        if ($null -eq $collection) { $collection = $resp.Body }
        $pageItems = @(if ($null -ne $collection) { $collection })
        foreach ($item in $pageItems) { $items.Add($item) }
        if ($pageItems.Count -lt $PageSize) { break }
    }
    return $items.ToArray()
}
