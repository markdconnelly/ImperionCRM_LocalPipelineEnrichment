function Invoke-ImperionThreadsRequest {
    <#
    .SYNOPSIS
        GET a Threads Graph API collection, following cursor paging, returning all items.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the Threads API (LocalPipeline #356,
        front-end Threads epic #1334 / ADR-0125). Threads is a SEPARATE API from the FB/IG Meta
        Graph: base https://graph.threads.net/v1.0, its own Threads OAuth long-lived token, no
        shared code or token with the Meta integration (0075). The token is carried as an
        `Authorization: Bearer` header — NEVER the `access_token` querystring — so request URLs
        this module builds are not secret-bearing.

        Collection responses arrive as { data: [...], paging: { cursors, next } }; single
        resources arrive bare — both shapes are tolerated (the Meta connect-layer pattern).
        Cursor paging follows `paging.next` until absent, capped by -MaxPages. Threads (like
        Meta) embeds the access token in the `paging.next` URL it returns; this helper STRIPS
        that parameter before following (the bearer header re-authenticates), so no
        secret-bearing URL is ever held, retried, or logged. The leading `/vNN.N/` path segment
        is re-pinned to the tested version so a multi-page call never drifts onto an untested
        API version (the Meta #135 precedent). Throttling (429/Retry-After) is handled by the
        retry core (Invoke-ImperionRestWithRetry).
    .PARAMETER Token
        Threads long-lived access token, sent as the bearer header. Held only in memory;
        never logged.
    .PARAMETER Uri
        Full request URL (https://graph.threads.net/v1.0/...) or a path relative to the
        v1.0 base (e.g. 'me/threads?fields=id,text').
    .PARAMETER MaxPages
        Safety cap on pages followed per call. Default 100.
    .EXAMPLE
        Invoke-ImperionThreadsRequest -Token $token -Uri 'me/threads?fields=id,text,timestamp'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Token,
        [Parameter(Mandatory)][string] $Uri,
        [ValidateRange(1, 1000)][int] $MaxPages = 100
    )

    # Single source of truth for the pinned Threads API version.
    $pinnedApiVersion = 'v1.0'
    if ($Uri -notmatch '^https?://') { $Uri = "https://graph.threads.net/$pinnedApiVersion/$($Uri.TrimStart('/'))" }
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    for ($page = 1; $page -le $MaxPages -and $next; $page++) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET

        # Probe for the data member's PRESENCE, not its value: an empty {data:[]} envelope
        # must not be mis-routed into the bare-resource branch (the Meta #133 garbage-row bug).
        $body = $resp.Body
        if ($null -ne $body -and $null -ne $body.PSObject.Properties['data']) {
            foreach ($item in @(Get-ImperionMember $body 'data')) { $items.Add($item) }
        }
        elseif ($null -ne $body) { $items.Add($body) }   # bare single resource

        $paging = Get-ImperionMember $resp.Body 'paging'
        $next = [string](Get-ImperionMember $paging 'next')
        if ($next) {
            # Threads' paging.next embeds access_token in the querystring; strip it (the
            # bearer header re-authenticates) so the URL we hold is never secret-bearing.
            $builder = [System.UriBuilder]$next
            $keptParameters = @($builder.Query.TrimStart('?') -split '&' |
                    Where-Object { $_ -and $_ -notmatch '^(?i)access_token=' })
            $builder.Query = $keptParameters -join '&'
            # Re-pin the version segment back to the tested pin (the Meta #135 precedent).
            $builder.Path = $builder.Path -replace '^/v\d+\.\d+/', "/$pinnedApiVersion/"
            $next = $builder.Uri.AbsoluteUri
        }
    }
    return $items.ToArray()
}
