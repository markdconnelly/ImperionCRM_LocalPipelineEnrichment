function Invoke-ImperionMetaRequest {
    <#
    .SYNOPSIS
        GET a Meta Graph API collection, following cursor paging, returning all items.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the Meta (Facebook/Instagram)
        Graph API, issue #126: base https://graph.facebook.com/v23.0, authenticated with
        the Business Manager system-user token (or a page token) carried as an
        Authorization: Bearer header — NEVER the access_token querystring parameter, so
        request URLs this module builds are not secret-bearing.

        Collection responses arrive as { data: [...], paging: { next } }; single
        resources arrive bare — both shapes are tolerated. Cursor paging follows
        paging.next until absent, capped by -MaxPages. Meta embeds the access token in
        the paging.next URL it returns; this helper STRIPS that parameter before
        following (the bearer header re-authenticates), so no secret-bearing URL is ever
        held, retried, or loggable. Throttling (429/Retry-After) is handled by the
        retry core (Invoke-ImperionRestWithRetry).
    .PARAMETER Token
        Meta access token (system-user or page token), sent as the bearer header.
        Held only in memory; never logged.
    .PARAMETER Uri
        Full request URL (https://graph.facebook.com/v23.0/...) or a path relative to
        the v23.0 base (e.g. '123456/posts?fields=message').
    .PARAMETER MaxPages
        Safety cap on pages followed per call. Default 100.
    .EXAMPLE
        Invoke-ImperionMetaRequest -Token $token -Uri '123456/posts?fields=message,created_time'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $Token,
        [Parameter(Mandatory)][string] $Uri,
        [ValidateRange(1, 1000)][int] $MaxPages = 100
    )

    if ($Uri -notmatch '^https?://') { $Uri = "https://graph.facebook.com/v23.0/$($Uri.TrimStart('/'))" }
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    for ($page = 1; $page -le $MaxPages -and $next; $page++) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET

        $data = Get-ImperionMember $resp.Body 'data'
        if ($null -ne $data) { foreach ($item in @($data)) { $items.Add($item) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # bare single resource

        $paging = Get-ImperionMember $resp.Body 'paging'
        $next = [string](Get-ImperionMember $paging 'next')
        if ($next) {
            # Meta's paging.next embeds access_token in the querystring; strip it (the
            # bearer header re-authenticates) so the URL we hold is never secret-bearing.
            $builder = [System.UriBuilder]$next
            $keptParameters = @($builder.Query.TrimStart('?') -split '&' |
                    Where-Object { $_ -and $_ -notmatch '^(?i)access_token=' })
            $builder.Query = $keptParameters -join '&'
            $next = $builder.Uri.AbsoluteUri
        }
    }
    return $items.ToArray()
}
