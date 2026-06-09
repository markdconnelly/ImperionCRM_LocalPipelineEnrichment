function Invoke-ImperionTelivyRequest {
    <#
    .SYNOPSIS
        GET a Telivy API collection with x-api-key auth, following pagination, returning all items.
    .DESCRIPTION
        Reusable connect-layer helper for the Telivy security-assessment API (CLAUDE.md §4).
        Aligned with the cloud Pipeline's Televy client (ImperionCRM_Pipeline
        src/shared/clients/televy.ts, ADR-0040): `x-api-key` header, JSON:API-style paging with
        records under `data` and the next-page URL under `links.next`. Pure: the API key is
        passed in (resolved from the SecretStore secret `Telivy-API-Key` by the caller), so the
        function holds no secret and is mockable. StrictMode-safe — absent fields yield $null.

        CONFIRM BEFORE LIVE USE: the Telivy base URL, resource paths, and the items/next
        property names are ASSUMPTIONS shared with the cloud Pipeline (flagged there too) — to
        verify against the live Telivy API on the first real pull. The Televy/Telivy spelling
        differs by surface: the SecretStore secret is `Telivy-API-Key`; the bronze source value
        written to Postgres must be `televy` (front-end assessment_artifact.source enum).
    .PARAMETER ApiKey
        Telivy API key (sent as the `x-api-key` header). From the SecretStore secret Telivy-API-Key.
    .PARAMETER Uri
        Full request URL (base + path), e.g. https://api.telivy.com/reports?page[size]=100.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'data'. If absent, the whole
        body is returned as a single item.
    .PARAMETER NextLinkProperty
        Dotted path to the next-page URL (cursor). Default 'links.next' (JSON:API).
    .EXAMPLE
        $key = Get-Secret -Name 'Telivy-API-Key' -AsPlainText -Vault ImperionStore
        Invoke-ImperionTelivyRequest -ApiKey $key -Uri 'https://api.telivy.com/reports?page[size]=100'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'data',
        [string] $NextLinkProperty = 'links.next'
    )

    $headers = @{ 'x-api-key' = $ApiKey; Accept = 'application/json' }
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
