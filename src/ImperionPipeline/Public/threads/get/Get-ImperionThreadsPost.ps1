function Get-ImperionThreadsPost {
    <#
    .SYNOPSIS
        Collect our own published Threads posts and flatten them to threads_posts bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the `threads` source (LocalPipeline #356,
        front-end Threads epic #1334 / ADR-0125). Pure first-party social data: flattens
        straight to Postgres, skips the IT Glue hub (the Meta precedent). Pages
        `/me/threads` via the connect layer (bearer-header auth; never a querystring token)
        with an optional -Since incremental lower bound. Target: bronze `threads_posts`
        (front-end migration 0208) → silver `interaction` (source `threads`, kind
        `social_post`, direction outbound) via Invoke-ImperionThreadsMerge (local merge
        ownership, ADR-0026). Returns rows; does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat (the Get-ImperionMetaPagePost precedent): the field list
        follows the published Threads API reference, but versions/permission tiers prune
        fields silently — an unreadable field comes back absent and its flat column lands
        NULL; nothing is lost (full payload in raw_payload). Verify against a live first run.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the Threads
        presence is Imperion's own first-party asset, not client data).
    .PARAMETER Since
        Optional incremental lower bound (ISO-8601 or unix time, passed as the documented
        `since` filter). Omit for a full backfill.
    .PARAMETER Token
        Threads token override. Defaults to the credential-registry resolution
        (Resolve-ImperionThreadsToken, ADR-0103).
    .PARAMETER MaxPages
        Paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionThreadsPost -Since '2026-06-01T00:00:00Z' | Set-ImperionThreadsPostToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $Since,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $Token = Resolve-ImperionThreadsToken -Token $Token -FailClosed

    $fields = 'id,username,text,media_type,media_url,permalink,shortcode,timestamp,' +
        'is_quote_post,reply_audience,owner'
    $uri = 'me/threads?fields={0}&limit=100' -f $fields
    if ($Since) { $uri += '&since=' + [uri]::EscapeDataString($Since) }

    $posts = @(Invoke-ImperionThreadsRequest -Token $Token -Uri $uri -MaxPages $MaxPages)

    $map = [ordered]@{
        threads_user_id = 'owner.id'
        username        = 'username'
        text_content    = 'text'
        media_type      = 'media_type'
        permalink       = 'permalink'
        shortcode       = 'shortcode'
        is_quote_post   = 'is_quote_post'
        reply_audience  = 'reply_audience'
        created_time    = 'timestamp'
    }

    $posts | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'threads' -TenantId $TenantId -ExternalIdProperty 'id'
}
