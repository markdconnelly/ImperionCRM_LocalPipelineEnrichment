function Get-ImperionMetaPagePost {
    <#
    .SYNOPSIS
        Collect Facebook Page feed posts and flatten them to facebook_posts bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source, issue #126. Pure
        CRM/marketing data: flattens straight to Postgres and skips the IT Glue hub
        (ADR-0006). Pages /{PageId}/posts via the connect layer (bearer-header auth;
        never a querystring token) with an optional -Since incremental lower bound.
        Target: bronze `facebook_posts` (front-end migration 0075) → silver `interaction`
        via Invoke-ImperionMetaMerge (local merge ownership, ADR-0013). Returns rows;
        does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat (the Get-ImperionKqmOpportunity precedent): the field
        list below follows Meta's published Page-feed reference, but Meta versions and
        permission tiers prune fields silently — a field the token cannot read simply
        comes back absent and its flat column lands NULL; nothing is lost (full payload
        in raw_payload). Verify against a live first run before trusting flat columns.
    .PARAMETER PageId
        The Facebook Page id to collect from (stamped onto each row as page_id).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the Page is
        Imperion's own first-party asset, not client data).
    .PARAMETER Since
        Optional incremental lower bound (ISO-8601 or unix time, passed as the
        documented `since` filter). Omit for a full backfill.
    .PARAMETER Token
        Meta system-user token override. Defaults to the SecretStore resolution
        (Resolve-ImperionMetaToken, ADR-0013).
    .PARAMETER MaxPages
        Paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionMetaPagePost -PageId '123456789' -Since '2026-06-01T00:00:00Z'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $PageId,
        [string] $TenantId,
        [string] $Since,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $Token = Resolve-ImperionMetaToken -Token $Token

    $fields = 'message,story,status_type,permalink_url,from,created_time,updated_time,is_published,' +
        'shares,comments.summary(true).limit(0),reactions.summary(true).limit(0)'
    $uri = '{0}/posts?fields={1}&limit=100' -f [uri]::EscapeDataString($PageId), $fields
    if ($Since) { $uri += '&since=' + [uri]::EscapeDataString($Since) }

    $posts = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri -MaxPages $MaxPages)
    foreach ($post in $posts) {
        $post | Add-Member -NotePropertyName '_imperionPageId' -NotePropertyValue $PageId -Force
    }

    $map = [ordered]@{
        page_id        = '_imperionPageId'
        message        = 'message'
        story          = 'story'
        status_type    = 'status_type'
        permalink_url  = 'permalink_url'
        from_id        = 'from.id'
        from_name      = 'from.name'
        created_time   = 'created_time'
        updated_time   = 'updated_time'
        is_published   = 'is_published'
        comment_count  = 'comments.summary.total_count'
        reaction_count = 'reactions.summary.total_count'
        share_count    = 'shares.count'
    }

    $posts | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'facebook' -TenantId $TenantId -ExternalIdProperty 'id'
}
