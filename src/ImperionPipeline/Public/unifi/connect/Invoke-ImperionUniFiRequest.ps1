function Invoke-ImperionUniFiRequest {
    <#
    .SYNOPSIS
        GET a UniFi API collection with X-API-Key auth, following nextToken/offset paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) shared by BOTH UniFi API families
        (issue #73 locked design, 2026-06-10):

        - **Console Network Integration API** (sites WITH a gateway/console):
          `https://<console-host>/proxy/network/integration/v1/...` — offset/limit paging
          (`offset`/`limit` query params, `totalCount` in the body).
        - **Cloud Site Manager API** (sites WITHOUT a gateway):
          `https://api.ui.com/v1/...` — cursor paging (`nextToken` in the body, echoed as
          a query parameter).

        Both send the per-customer API key as the `X-API-Key` header. Pure and
        StrictMode-safe: the key is passed in (company credential — Key Vault
        `conn-company-unifi` JSON blob), so the function holds no secret and is mockable.

        CONFIRM BEFORE LIVE USE: items/paging property names (`data`, `nextToken`,
        `offset`/`totalCount`) are ASSUMPTIONS from the published UniFi API docs — verify
        against the live controller on the first pull, per connection type.
    .PARAMETER ApiKey
        UniFi API key (per-customer company credential), sent as X-API-Key.
    .PARAMETER Uri
        Full request URL (base + path) for the first page.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'data'. If absent,
        the whole body is returned as a single item.
    .EXAMPLE
        Invoke-ImperionUniFiRequest -ApiKey $key -Uri 'https://api.ui.com/v1/devices'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'data'
    )

    $headers = @{ 'X-API-Key' = $ApiKey; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $requestParameters = @{ Uri = $next; Headers = $headers; Method = 'GET' }
        $resp = Invoke-ImperionRestWithRetry @requestParameters
        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        if ($null -ne $collection) { $collection | ForEach-Object { $items.Add($_) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # single resource / non-paged shape

        $next = $null
        # Cloud Site Manager cursor: body carries nextToken until the last page.
        $nextToken = Get-ImperionMember $resp.Body 'nextToken'
        if ($nextToken) {
            $separator = if ($requestParameters.Uri.Contains('?')) { '&' } else { '?' }
            $base = $requestParameters.Uri -replace '([?&])nextToken=[^&]*', '$1' -replace '[?&]$', ''
            $separator = if ($base.Contains('?')) { '&' } else { '?' }
            $next = '{0}{1}nextToken={2}' -f $base, $separator, [uri]::EscapeDataString([string]$nextToken)
        }
        else {
            # Console offset paging: advance while offset+count < totalCount.
            $totalCount = Get-ImperionMember $resp.Body 'totalCount'
            $offset = Get-ImperionMember $resp.Body 'offset'
            $count = Get-ImperionMember $resp.Body 'count'
            if ($null -ne $totalCount -and $null -ne $offset -and $null -ne $count) {
                $nextOffset = [int]$offset + [int]$count
                if ($nextOffset -lt [int]$totalCount -and [int]$count -gt 0) {
                    $base = $requestParameters.Uri -replace '([?&])offset=\d*', '$1' -replace '[?&]$', ''
                    $separator = if ($base.Contains('?')) { '&' } else { '?' }
                    $next = '{0}{1}offset={2}' -f $base, $separator, $nextOffset
                }
            }
        }
    }
    return $items.ToArray()
}
