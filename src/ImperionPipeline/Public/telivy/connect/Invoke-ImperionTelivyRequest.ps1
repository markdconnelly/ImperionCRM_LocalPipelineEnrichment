function Invoke-ImperionTelivyRequest {
    <#
    .SYNOPSIS
        GET a Telivy API collection with bearer auth, following pagination, returning all items.
    .DESCRIPTION
        Reusable connect-layer helper for the Telivy security-assessment API (CLAUDE.md §4).
        Sends a bearer token, pages by following a cursor property, and returns the collected
        items. Pure: the API key is passed in (resolved from the SecretStore by the caller),
        so the function is mockable and holds no secret.

        CONFIRM BEFORE LIVE USE: the Telivy base URL, resource paths, the collection property
        name (-ItemsProperty) and the pagination cursor property (-NextLinkProperty) must be
        verified against the current Telivy API documentation. The defaults ('data' / 'next')
        are common conventions, not a verified contract — see docs/integrations (telivy).
    .PARAMETER AccessToken
        Telivy API bearer token / key.
    .PARAMETER Uri
        Full request URL (base + path), e.g. https://api.telivy.com/v1/assessments.
    .PARAMETER ItemsProperty
        Name of the collection property in the response body. Default 'data'. If the body has
        no such property the whole body is returned as a single item.
    .PARAMETER NextLinkProperty
        Name of the response property holding the next-page URL (cursor). Default 'next'.
    .EXAMPLE
        $key = Get-Secret -Name TelivyApiKey -AsPlainText -Vault ImperionStore
        Invoke-ImperionTelivyRequest -AccessToken $key -Uri 'https://api.telivy.com/v1/assessments'
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
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # single resource / non-paged shape
        $next = & $readProp $resp.Body $NextLinkProperty
    }
    return $items.ToArray()
}
