function Invoke-ImperionDarkWebIdRequest {
    <#
    .SYNOPSIS
        GET a Dark Web ID (ID Agent) API collection with bearer auth, following pagination.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4). Aligned with the cloud Pipeline's Dark Web
        ID client (ImperionCRM_Pipeline src/shared/clients/darkwebid.ts, ADR-0040): a single API
        key sent as `Authorization: Bearer <apiKey>`, JSON:API-style paging with records under
        `data` and the next-page URL under `links.next`. Pure and StrictMode-safe: the key is
        passed in (a company credential — Key Vault `conn-company-darkwebid` in the cloud), so
        the function holds no secret and is mockable.

        CONFIRM BEFORE LIVE USE: the Dark Web ID base URL, resource paths, auth scheme, and the
        items/next property names are ASSUMPTIONS shared with the cloud Pipeline (flagged there
        too: the scheme "could be x-api-key / Basic / OAuth") — verify against the live API on
        the first real pull.
    .PARAMETER ApiKey
        Dark Web ID API key, sent as the bearer credential.
    .PARAMETER Uri
        Full request URL (base + path), e.g. https://api.darkwebid.com/compromises?page[size]=100.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'data'. If absent, the whole
        body is returned as a single item.
    .PARAMETER NextLinkProperty
        Dotted path to the next-page URL (cursor). Default 'links.next' (JSON:API).
    .EXAMPLE
        Invoke-ImperionDarkWebIdRequest -ApiKey $key -Uri 'https://api.darkwebid.com/compromises?page[size]=100'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'data',
        [string] $NextLinkProperty = 'links.next'
    )

    $headers = @{ Authorization = "Bearer $ApiKey"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET
        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        if ($null -ne $collection) { $collection | ForEach-Object { $items.Add($_) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # single resource / non-paged shape
        $next = Get-ImperionPropertyPath -InputObject $resp.Body -Path $NextLinkProperty
    }
    return $items.ToArray()
}
