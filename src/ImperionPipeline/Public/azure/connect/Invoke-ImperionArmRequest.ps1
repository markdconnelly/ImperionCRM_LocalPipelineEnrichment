function Invoke-ImperionArmRequest {
    <#
    .SYNOPSIS
        GET an Azure Resource Manager collection, following nextLink, returning all items.
    .PARAMETER Path
        ARM path including api-version (e.g. '/subscriptions?api-version=2022-12-01') or a full URL.
    .PARAMETER AccessToken
        ARM access token from Get-ImperionAccessToken (resource https://management.azure.com/.default).
    .EXAMPLE
        Invoke-ImperionArmRequest -Path '/subscriptions?api-version=2022-12-01' -AccessToken $tok
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $AccessToken
    )

    $uri = if ($Path -match '^https?://') { $Path } else { "https://management.azure.com$($Path)" }
    $headers = @{ Authorization = "Bearer $AccessToken" }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $uri
    while ($next) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET
        $value = Get-ImperionMember $resp.Body 'value'
        if ($null -ne $value) { $value | ForEach-Object { $items.Add($_) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # single resource (no 'value' collection)
        $next = Get-ImperionMember $resp.Body 'nextLink'
    }
    return $items.ToArray()
}
