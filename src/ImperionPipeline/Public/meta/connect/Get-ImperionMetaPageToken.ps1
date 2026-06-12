function Get-ImperionMetaPageToken {
    <#
    .SYNOPSIS
        Resolve a Facebook Page access token (or discover the pages the system user manages).
    .DESCRIPTION
        Connect-layer helper (issue #126). Several Page edges — /conversations (the page
        inbox) above all — reject the Business Manager system-user token and require a
        PAGE access token. Two modes:

          * -PageId: GET /{page-id}?fields=access_token with the system-user token and
            return that page's token (a string, held only in memory — NEVER logged, never
            written anywhere).
          * -Discover: GET /me/accounts and return one row per page the system user can
            see ({ page_id; page_name; page_token }) — the bootstrap path for finding the
            page id to configure. Do not dump these rows to logs; page_token is a secret.

        Token resolution for the system-user token: explicit -Token, else the SecretStore
        secret named by MetaSystemUserToken (no Key Vault fallback — ADR-0013). Requires
        Initialize-ImperionContext.
    .PARAMETER PageId
        The Facebook Page id whose page access token to fetch.
    .PARAMETER Discover
        List the pages (and their tokens) visible to the system user via /me/accounts.
    .PARAMETER Token
        Meta system-user token override. Defaults to the SecretStore resolution above.
    .OUTPUTS
        ById: the page access token [string]. Discover: { page_id; page_name; page_token } rows.
    .EXAMPLE
        $pageToken = Get-ImperionMetaPageToken -PageId '123456789'
    .EXAMPLE
        Get-ImperionMetaPageToken -Discover | Select-Object page_id, page_name   # never select page_token into output you keep
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    [OutputType([string], [pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')][string] $PageId,
        [Parameter(Mandatory, ParameterSetName = 'Discover')][switch] $Discover,
        [string] $Token
    )

    $Token = Resolve-ImperionMetaToken -Token $Token

    if ($Discover) {
        $pages = Invoke-ImperionMetaRequest -Token $Token -Uri 'me/accounts?fields=id,name,access_token'
        foreach ($page in $pages) {
            [pscustomobject]@{
                page_id    = [string](Get-ImperionMember $page 'id')
                page_name  = [string](Get-ImperionMember $page 'name')
                page_token = [string](Get-ImperionMember $page 'access_token')
            }
        }
        return
    }

    $resource = Invoke-ImperionMetaRequest -Token $Token `
        -Uri ('{0}?fields=access_token' -f [uri]::EscapeDataString($PageId))
    $pageToken = [string](Get-ImperionMember (@($resource) | Select-Object -First 1) 'access_token')
    if (-not $pageToken) {
        throw "No page access token returned for page $PageId - check pages_show_list/pages_manage_metadata on the system user."
    }
    return $pageToken
}
