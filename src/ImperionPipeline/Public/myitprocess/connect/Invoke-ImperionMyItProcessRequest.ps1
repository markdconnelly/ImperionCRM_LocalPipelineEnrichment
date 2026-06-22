function Invoke-ImperionMyItProcessRequest {
    <#
    .SYNOPSIS
        GET a myITprocess API collection with mitp-api-key header auth, following page-based paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the myITprocess Reporting API (issue #195,
        ADR-0018): the vCIO strategic-advisory layer (initiatives, alignment scores,
        recommendations) scoped to an ACCOUNT, not a device. The API key is sent as the
        `mitp-api-key` header, HTTPS+JSON, pull-only (no webhooks reach a home server — ADR-0001).
        Header auth means request URLs are NOT secret-bearing.

        VERIFIED LIVE (2026-06-21, issue #297) against the seeded prod credential: base host
        `https://reporting.live.myitprocess.com/public-api/v1`, header `mitp-api-key`, response
        wrapper `{ page, pageSize, totalCount, items }` (a direct GET returned HTTP 200; the
        Celerium MyITProcess-PowerShellWrapper + Kaseya Swagger corroborate). The earlier
        `api.myitprocess.com` / `api_token` / `data` constants were placeholders and all wrong.

        This helper walks `?page=N` from 1 and stops on the FIRST of: an empty page, the
        accumulated count reaching `totalCount`, or (only when no totalCount is present, i.e. a
        bare-array body) a short page — hard-capped by -MaxPages. Preferring totalCount over a
        short-page heuristic is deliberate: the server may page smaller than -PageSize, which a
        short-page stop would mistake for the end and silently drop rows. Throttling
        (429 + Retry-After) and transient 5xx are handled by the retry core.
    .PARAMETER ApiKey
        myITprocess API key (MSP-wide vendor credential), sent as the mitp-api-key header. Held
        only in memory.
    .PARAMETER Uri
        Full request URL (base + path), e.g.
        'https://reporting.live.myitprocess.com/public-api/v1/recommendations'.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'items'. If absent, the whole
        body is returned as a single item (StrictMode-safe).
    .PARAMETER TotalCountProperty
        Dotted path to the total-row count in the response wrapper. Default 'totalCount'. When
        present, paging stops once the accumulated item count reaches it (server-page-size safe).
    .PARAMETER PageSize
        Short-page threshold used ONLY as a fallback when the body carries no TotalCountProperty.
        Default 100.
    .PARAMETER MaxPages
        Safety cap on pages per call (runaway guard). Default 200.
    .EXAMPLE
        Invoke-ImperionMyItProcessRequest -ApiKey $key -Uri 'https://reporting.live.myitprocess.com/public-api/v1/recommendations'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'items',
        [string] $TotalCountProperty = 'totalCount',
        [ValidateRange(1, 500)][int] $PageSize = 100,
        [ValidateRange(1, 500)][int] $MaxPages = 200
    )

    $headers = @{ 'mitp-api-key' = $ApiKey; Accept = 'application/json' }
    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    $items = [System.Collections.Generic.List[object]]::new()

    for ($page = 1; $page -le $MaxPages; $page++) {
        $pageUri = '{0}{1}page={2}' -f $Uri, $separator, $page
        $resp = Invoke-ImperionRestWithRetry -Uri $pageUri -Headers $headers -Method GET

        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        $pageItems = @(if ($null -ne $collection) { $collection } elseif ($null -ne $resp.Body) { $resp.Body })
        foreach ($item in $pageItems) { $items.Add($item) }

        # Stop conditions, most authoritative first. The live wrapper is
        # { page, pageSize, totalCount, items }, so prefer totalCount — the server may page
        # smaller than -PageSize, which would make a short-page heuristic stop early and drop
        # rows. Fall back to the short-page heuristic only when no totalCount is present (a
        # bare-array body), and always stop on an empty page.
        if ($pageItems.Count -eq 0) { break }
        $totalCount = Get-ImperionPropertyPath -InputObject $resp.Body -Path $TotalCountProperty
        if ($null -ne $totalCount) {
            if ($items.Count -ge [int] $totalCount) { break }
        }
        elseif ($pageItems.Count -lt $PageSize) { break }
    }
    return $items.ToArray()
}
