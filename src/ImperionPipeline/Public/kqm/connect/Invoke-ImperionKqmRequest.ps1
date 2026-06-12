function Invoke-ImperionKqmRequest {
    <#
    .SYNOPSIS
        GET a Kaseya Quote Manager (KQM) collection with ?apikey= auth, following page=N paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the KQM read-only REST API
        (verified facts, issue #98): base https://api.kaseyaquotemanager.com/v1, the API
        key passed as the `apikey` querystring parameter, pages numbered from 1 at up to
        100 results per page, limits 60 calls/min + 20,000/day, pull-only (no webhooks).
        Docs: api.dattocommerce.com/docs.

        SECRET-BEARING URLS: because the key rides in the querystring, every request URL
        is itself a secret. This helper appends the key internally and the retry core
        (Invoke-ImperionRestWithRetry) redacts apikey-style parameters from all log lines
        and error text — never log or echo a full KQM URL anywhere else either.

        Paging stops when a page returns fewer than -PageSize items. -MaxPages caps a
        runaway loop well inside the 20k/day budget. Throttling (429 + Retry-After) is
        handled by the retry core. The collection shape (bare array vs wrapped) is
        tolerated both ways pending live verification (Get-ImperionKqmFieldName).
    .PARAMETER ApiKey
        KQM API key, appended as the apikey querystring parameter. Held only in memory.
    .PARAMETER Uri
        Full request URL WITHOUT the apikey (base + path + any filters, e.g.
        "https://api.kaseyaquotemanager.com/v1/quote?modifiedAfter=...").
    .PARAMETER PageSize
        Page-full threshold (API max/default 100): a page with fewer items ends the loop.
    .PARAMETER MaxPages
        Safety cap on pages per call. Default 190 (~19k rows), inside the 20k/day limit.
    .EXAMPLE
        Invoke-ImperionKqmRequest -ApiKey $key -Uri 'https://api.kaseyaquotemanager.com/v1/quote'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $Uri,
        [ValidateRange(1, 100)][int] $PageSize = 100,
        [ValidateRange(1, 200)][int] $MaxPages = 190
    )

    $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
    $items = [System.Collections.Generic.List[object]]::new()

    for ($page = 1; $page -le $MaxPages; $page++) {
        $pageUri = '{0}{1}page={2}&apikey={3}' -f $Uri, $separator, $page, [uri]::EscapeDataString($ApiKey)
        $resp = Invoke-ImperionRestWithRetry -Uri $pageUri -Headers @{ Accept = 'application/json' } -Method GET

        # Tolerate both a bare JSON array and a single (non-paged) resource object. The @(if)
        # collection keeps $pageItems a real array even when the body is empty (StrictMode-safe).
        $pageItems = @(if ($null -ne $resp.Body) { $resp.Body })
        foreach ($item in $pageItems) { $items.Add($item) }
        if ($pageItems.Count -lt $PageSize) { break }
    }
    return $items.ToArray()
}
