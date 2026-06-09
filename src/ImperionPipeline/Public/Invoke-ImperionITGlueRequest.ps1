function Invoke-ImperionITGlueRequest {
    <#
    .SYNOPSIS
        Call the IT Glue JSON:API, paging through links.next, returning all `data` records (or the raw response for writes).
    .DESCRIPTION
        GET requests page through the full collection. Non-GET requests (POST/PATCH for the
        flexible-asset hub) return the single parsed response. The API key comes from the
        SecretStore — pass it in, never hard-code.
    .PARAMETER Path
        IT Glue path (e.g. 'organizations', 'flexible_assets') or a full URL.
    .PARAMETER ApiKey
        IT Glue API key (from the SecretStore).
    .PARAMETER Method
        HTTP method; defaults to GET.
    .PARAMETER Body
        Request body object for POST/PATCH (will be JSON-encoded).
    .PARAMETER Query
        Optional query string (e.g. 'sort=-updated-at&page[size]=1000&filter[organization_id]=123').
    .PARAMETER BaseUri
        Regional API base; defaults to https://api.itglue.com.
    .EXAMPLE
        Invoke-ImperionITGlueRequest -Path organizations -ApiKey $k -Query 'sort=-updated-at&page[size]=1000'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ApiKey,
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string] $Method = 'GET',
        $Body,
        [string] $Query,
        [string] $BaseUri = 'https://api.itglue.com'
    )

    $headers = @{ 'x-api-key' = $ApiKey; 'Content-Type' = 'application/vnd.api+json' }
    $uri = if ($Path -match '^https?://') { $Path } else { "$BaseUri/$($Path.TrimStart('/'))" }
    if ($Query) { $uri += ($(if ($uri.Contains('?')) { '&' } else { '?' }) + $Query) }

    if ($Method -ne 'GET') {
        $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 20 } else { $null }
        $resp = Invoke-ImperionRestWithRetry -Uri $uri -Headers $headers -Method $Method -Body $json -ContentType 'application/vnd.api+json'
        return $resp.Body
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $uri
    while ($next) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET
        if ($null -ne $resp.Body.data) { $resp.Body.data | ForEach-Object { $items.Add($_) } }
        $next = if ($resp.Body.links) { $resp.Body.links.next } else { $null }
    }
    return $items.ToArray()
}
