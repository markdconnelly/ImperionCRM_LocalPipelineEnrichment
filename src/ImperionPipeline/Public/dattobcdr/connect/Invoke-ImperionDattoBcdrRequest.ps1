function Invoke-ImperionDattoBcdrRequest {
    <#
    .SYNOPSIS
        GET a Datto BCDR API collection with bearer auth, following page-based paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the Datto BCDR / backup REST API
        (issue #195, ADR-0018): the API key sent as `Authorization: Bearer <apiKey>`, HTTPS+JSON,
        pull-only (no webhooks reach a home server — ADR-0001). Header auth means request URLs
        are NOT secret-bearing.

        Datto BCDR exposes per-device backup posture (protected/unprotected, last-good-backup,
        last-screenshot-verification). This helper walks `?page=N` from 1, stopping when a page
        returns fewer than -PageSize items, hard-capped by -MaxPages. Throttling (429 +
        Retry-After) and transient 5xx are handled by the retry core.

        CONFIRM BEFORE LIVE USE: the exact base host, the resource path, the auth header form,
        the pagination scheme, and the collection wrapper are modeled from the documented API but
        UNVERIFIED against the real account until the key lands (the KQM/EasyDMARC precedent) —
        tolerate both a wrapped (`items`) and a bare array body, confirm on the first real pull.
    .PARAMETER ApiKey
        Datto BCDR API key (MSP-wide vendor credential), sent as the bearer. Held only in memory.
    .PARAMETER Uri
        Full request URL (base + path), e.g. 'https://api.datto.com/v1/bcdr/agents'.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'items'. If absent, the
        whole body is returned as a single item (StrictMode-safe).
    .PARAMETER PageSize
        Page-full threshold: a page with fewer items ends the loop. Default 100.
    .PARAMETER MaxPages
        Safety cap on pages per call (runaway guard). Default 200.
    .EXAMPLE
        Invoke-ImperionDattoBcdrRequest -ApiKey $key -Uri 'https://api.datto.com/v1/bcdr/agents'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'items',
        [ValidateRange(1, 500)][int] $PageSize = 100,
        [ValidateRange(1, 500)][int] $MaxPages = 200
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
        if ($pageItems.Count -lt $PageSize) { break }
    }
    return $items.ToArray()
}
