function Invoke-ImperionDarkWebIdRequest {
    <#
    .SYNOPSIS
        GET a Dark Web ID (ID Agent) API collection with bearer auth, following pagination.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4). Sends the bearer token from
        Connect-ImperionDarkWebId, pages by following a cursor property, and returns the
        collected items. Pure and StrictMode-safe: the token is passed in, so the function
        holds no secret and is mockable.

        CONFIRM BEFORE LIVE USE: the Dark Web ID base URL, resource paths, the collection
        property name (-ItemsProperty) and the pagination cursor property (-NextLinkProperty)
        must be verified against the current ID Agent / Dark Web ID Partner API documentation.
        The defaults are common conventions, not a verified contract.
    .PARAMETER AccessToken
        Bearer token from Connect-ImperionDarkWebId.
    .PARAMETER Uri
        Full request URL (base + path), e.g. https://api.example/v1/compromises?domain=acme.com.
    .PARAMETER ItemsProperty
        Collection property in the response body. Default 'data'. If absent, the whole body is
        returned as a single item.
    .PARAMETER NextLinkProperty
        Response property holding the next-page URL (cursor). Default 'next'.
    .EXAMPLE
        $tok = Connect-ImperionDarkWebId -ClientId $id -ClientSecret $sec -TokenEndpoint $url
        Invoke-ImperionDarkWebIdRequest -AccessToken $tok -Uri 'https://api.example/v1/compromises?domain=acme.com'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $AccessToken,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'data',
        [string] $NextLinkProperty = 'next'
    )

    # StrictMode-safe property read: returns $null if the property is absent rather than throwing.
    $readProp = {
        param($Object, $Name)
        if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.PSObject.Properties[$Name].Value } else { $null }
    }

    $headers = @{ Authorization = "Bearer $AccessToken"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET
        $collection = & $readProp $resp.Body $ItemsProperty
        if ($null -ne $collection) { $collection | ForEach-Object { $items.Add($_) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }
        $next = & $readProp $resp.Body $NextLinkProperty
    }
    return $items.ToArray()
}
