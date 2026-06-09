function Invoke-ImperionAutotaskRequest {
    <#
    .SYNOPSIS
        Query an Autotask REST entity, following pagination, returning all items.
    .DESCRIPTION
        Issues GET {base}/{Entity}/query?search=<json> against a zone base URL (from
        Get-ImperionAutotaskZone), follows pageDetails.nextPageUrl to the end, and returns the
        flattened item set. 429/503 backoff is handled by the shared retry core. Pure
        connect-layer helper (CLAUDE.md §4): pass the zone base + auth headers in; the
        get-layer builds the flat table.
    .PARAMETER ApiBaseUrl
        The zone base URL ending in /V1.0 (from Get-ImperionAutotaskZone).
    .PARAMETER Headers
        Autotask auth headers (ApiIntegrationCode, UserName, Secret, Content-Type).
    .PARAMETER Entity
        The Autotask entity name, e.g. Companies, Contacts, Contracts, Tickets.
    .PARAMETER Filter
        One or more filter conditions (each a hashtable like @{ op='gte'; field='id'; value=0 }).
        Defaults to "all records" (id gte 0), the Autotask idiom for an unbounded query.
    .EXAMPLE
        $base = Get-ImperionAutotaskZone -UserName $u -Headers $h
        Invoke-ImperionAutotaskRequest -ApiBaseUrl $base -Headers $h -Entity Companies
    .EXAMPLE
        $since = @{ op = 'gte'; field = 'lastActivityDate'; value = (Get-Date).AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ') }
        Invoke-ImperionAutotaskRequest -ApiBaseUrl $base -Headers $h -Entity Tickets -Filter $since
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $ApiBaseUrl,
        [Parameter(Mandatory)][hashtable] $Headers,
        [Parameter(Mandatory)][string] $Entity,
        [hashtable[]] $Filter = @(@{ op = 'gte'; field = 'id'; value = 0 })
    )

    $search = @{ filter = $Filter } | ConvertTo-Json -Depth 6 -Compress
    $items = [System.Collections.Generic.List[object]]::new()
    $next = '{0}/{1}/query?search={2}' -f $ApiBaseUrl.TrimEnd('/'), $Entity, [uri]::EscapeDataString($search)

    while ($next) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $Headers -Method GET
        $records = Get-ImperionMember $resp.Body 'items'
        if ($null -ne $records) { $records | ForEach-Object { $items.Add($_) } }
        $next = Get-ImperionPropertyPath -InputObject $resp.Body -Path 'pageDetails.nextPageUrl'
    }
    return $items.ToArray()
}
