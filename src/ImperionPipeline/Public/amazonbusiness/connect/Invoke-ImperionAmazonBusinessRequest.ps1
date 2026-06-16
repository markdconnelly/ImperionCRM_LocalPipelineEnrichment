function Invoke-ImperionAmazonBusinessRequest {
    <#
    .SYNOPSIS
        GET an Amazon Business API collection with bearer auth, following page/cursor paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the Amazon Business read-only REST/OAuth
        API (capability review, issue #198 — modeled from the public Amazon Business API docs):
        the access token sent as `Authorization: Bearer <token>`, HTTPS+JSON, pull-only (no
        home-server-receivable webhooks) — so the scheduled bulk poll belongs in this repo per the
        cloud/local boundary (ADR-0001). Header auth means request URLs are NOT secret-bearing.

        Paging follows the common Amazon Business cursor envelope: records under a `data`/`orders`
        array and an opaque `nextToken`/`nextPageToken` continuation token. This helper walks the
        cursor (re-issuing the same URI with `?nextToken=<token>`), stopping when no token is
        returned, hard-capped by -MaxPages. Throttling (429 + Retry-After) and transient 5xx are
        handled by the retry core.

        CONFIRM BEFORE LIVE USE: the exact base URL, resource paths, OAuth/auth header form, the
        pagination scheme (cursor vs page), and field names are ASSUMPTIONS from the public docs
        (no live credential yet — issue #198). Verify on the first real pull and tighten the flatten
        map then; misses land NULL and the raw payload keeps everything.
    .PARAMETER AccessToken
        Amazon Business access token (company credential), sent as the bearer. Held only in memory.
    .PARAMETER Uri
        Full request URL (base + path), e.g. https://na.business-api.amazon.com/orders/v1/orders.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'data'. If absent, the whole
        body is returned as a single item (StrictMode-safe).
    .PARAMETER NextTokenProperty
        Dotted path to the continuation token in the body. Default 'nextToken'.
    .PARAMETER MaxPages
        Safety cap on pages per call (runaway guard). Default 100.
    .EXAMPLE
        Invoke-ImperionAmazonBusinessRequest -AccessToken $tok -Uri 'https://na.business-api.amazon.com/orders/v1/orders'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $AccessToken,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'data',
        [string] $NextTokenProperty = 'nextToken',
        [ValidateRange(1, 500)][int] $MaxPages = 100
    )

    $headers = @{ Authorization = "Bearer $AccessToken"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()
    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    $nextToken = $null

    for ($page = 1; $page -le $MaxPages; $page++) {
        $pageUri = if ($nextToken) { '{0}{1}nextToken={2}' -f $Uri, $separator, [uri]::EscapeDataString([string]$nextToken) } else { $Uri }
        $resp = Invoke-ImperionRestWithRetry -Uri $pageUri -Headers $headers -Method GET

        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        $pageItems = @(if ($null -ne $collection) { $collection } elseif ($null -ne $resp.Body) { $resp.Body })
        foreach ($item in $pageItems) { $items.Add($item) }

        $nextToken = Get-ImperionPropertyPath -InputObject $resp.Body -Path $NextTokenProperty
        if ($null -eq $nextToken -or "$nextToken" -eq '') { break }
    }
    return $items.ToArray()
}
