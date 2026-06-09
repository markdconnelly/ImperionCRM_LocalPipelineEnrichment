function Invoke-ImperionGraphRequest {
    <#
    .SYNOPSIS
        GET a Microsoft Graph collection, following @odata.nextLink, returning all items.
    .PARAMETER Uri
        Full Graph URL (e.g. https://graph.microsoft.com/v1.0/servicePrincipals) or a path.
    .PARAMETER AccessToken
        Graph access token from Get-ImperionAccessToken.
    .PARAMETER Select
        Optional $select fields to trim the payload.
    .EXAMPLE
        Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -AccessToken $tok
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][string] $AccessToken,
        [string] $Select
    )

    if ($Uri -notmatch '^https?://') { $Uri = "https://graph.microsoft.com/v1.0/$($Uri.TrimStart('/'))" }
    if ($Select) { $Uri += ($(if ($Uri.Contains('?')) { '&' } else { '?' }) + '$select=' + $Select) }

    $headers = @{ Authorization = "Bearer $AccessToken"; 'ConsistencyLevel' = 'eventual' }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET
        if ($null -ne $resp.Body.value) { $resp.Body.value | ForEach-Object { $items.Add($_) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # single resource
        $next = $resp.Body.'@odata.nextLink'
    }
    return $items.ToArray()
}
