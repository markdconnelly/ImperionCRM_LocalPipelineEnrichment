function Get-ImperionAutotaskZone {
    <#
    .SYNOPSIS
        Resolve the Autotask REST API base URL (zone) for an API user.
    .DESCRIPTION
        Autotask partitions accounts across regional zones; every data query must target the
        account's own zone base URL. This calls the unauthenticated-zone discovery endpoint
        (zoneInformation) with the API credentials, then returns the versioned base URL
        (e.g. https://webservices15.autotask.net/atservicesrest/V1.0) ready for
        Invoke-ImperionAutotaskRequest. The result is cached per UserName for the session so
        the discovery call runs once. Reusable connect-layer helper (CLAUDE.md §4).
    .PARAMETER UserName
        The Autotask API user (the api-only account's UserName / api-user).
    .PARAMETER Headers
        The Autotask auth headers: ApiIntegrationCode, UserName, Secret (and Content-Type).
        Build these from the SecretStore in the calling get-layer function or task.
    .PARAMETER Force
        Bypass the per-user cache and re-resolve.
    .EXAMPLE
        $headers = @{ ApiIntegrationCode = $code; UserName = $user; Secret = $secret; 'Content-Type' = 'application/json' }
        $base = Get-ImperionAutotaskZone -UserName $user -Headers $headers
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $UserName,
        [Parameter(Mandatory)][hashtable] $Headers,
        [switch] $Force
    )

    if (-not $script:ImperionAutotaskZoneCache) { $script:ImperionAutotaskZoneCache = @{} }
    if (-not $Force -and $script:ImperionAutotaskZoneCache.ContainsKey($UserName)) {
        return $script:ImperionAutotaskZoneCache[$UserName]
    }

    $discoveryUri = 'https://webservices.autotask.net/atservicesrest/v1.0/zoneInformation?user={0}' -f [uri]::EscapeDataString($UserName)
    $zone = (Invoke-ImperionRestWithRetry -Uri $discoveryUri -Headers $Headers -Method GET).Body
    if (-not $zone.url) {
        throw "Autotask zoneInformation returned no url for user '$UserName'."
    }

    $baseUrl = ($zone.url.TrimEnd('/')) + '/V1.0'
    $script:ImperionAutotaskZoneCache[$UserName] = $baseUrl
    return $baseUrl
}
