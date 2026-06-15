function Invoke-ImperionEasyDmarcRequest {
    <#
    .SYNOPSIS
        GET an EasyDMARC API collection with bearer auth, following page-based paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the EasyDMARC read-only REST API
        (capability review, issue #122 — public docs only: developers.easydmarc.com):
        base https://api.easydmarc.com, the API key sent as `Authorization: Bearer <apiKey>`,
        HTTPS+JSON, pull-only (no webhooks surfaced) — so the scheduled bulk poll belongs in
        this repo per the cloud/local boundary. Header auth means request URLs are NOT
        secret-bearing.

        Paging follows the common EasyDMARC envelope: records under a `data` array and a
        `meta`/pagination block carrying the current page and a total/last-page count. This
        helper walks `?page=N` from 1, stopping when a page returns fewer than -PageSize
        items OR a reported last page is reached, hard-capped by -MaxPages. Throttling
        (429 + Retry-After) and transient 5xx are handled by the retry core.

        CONFIRM BEFORE LIVE USE: the exact base URL, resource paths, auth header form, the
        pagination scheme (page vs cursor), and field names are ASSUMPTIONS from the public
        docs (no live key yet — issue #122). Verify on the first real pull and tighten the
        flatten map then; misses land NULL and the raw payload keeps everything.
    .PARAMETER ApiKey
        EasyDMARC API key (company credential), sent as the bearer. Held only in memory.
    .PARAMETER Uri
        Full request URL (base + path), e.g. https://api.easydmarc.com/domains.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'data'. If absent, the
        whole body is returned as a single item (StrictMode-safe).
    .PARAMETER PageSize
        Page-full threshold: a page with fewer items ends the loop. Default 100.
    .PARAMETER MaxPages
        Safety cap on pages per call (runaway guard). Default 100.
    .EXAMPLE
        Invoke-ImperionEasyDmarcRequest -ApiKey $key -Uri 'https://api.easydmarc.com/domains'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'data',
        [ValidateRange(1, 500)][int] $PageSize = 100,
        [ValidateRange(1, 500)][int] $MaxPages = 100
    )

    $headers = @{ Authorization = "Bearer $ApiKey"; Accept = 'application/json' }
    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    $items = [System.Collections.Generic.List[object]]::new()

    for ($page = 1; $page -le $MaxPages; $page++) {
        $pageUri = '{0}{1}page={2}' -f $Uri, $separator, $page
        $resp = Invoke-ImperionRestWithRetry -Uri $pageUri -Headers $headers -Method GET

        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        $pageItems = @(if ($null -ne $collection) { $collection } elseif ($null -ne $resp.Body) { $resp.Body })
        foreach ($item in $pageItems) { $items.Add($item) }

        # Stop on a short page (last page) or when a reported last/total page is reached.
        if ($pageItems.Count -lt $PageSize) { break }
        $lastPage = Get-ImperionPropertyPath -InputObject $resp.Body -Path 'meta.last_page'
        if ($null -ne $lastPage -and $page -ge [int]$lastPage) { break }
    }
    return $items.ToArray()
}
