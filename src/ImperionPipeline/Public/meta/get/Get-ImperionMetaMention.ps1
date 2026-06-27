function Get-ImperionMetaMention {
    <#
    .SYNOPSIS
        Collect Meta brand mentions (FB Page tagged posts + IG tags) and flatten them to meta_mentions bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source — the deferred MENTIONS half of
        social-plane slice H (front-end Social plane epic #1338 / ADR-0124 decision 2; LP #391,
        front-end #1365). Two edges, polled per-network and FAIL-SOFT (one network's error never
        aborts the other, the per-(source) isolation rule §1):

          - Facebook: GET /{page-id}/tagged — posts in which our Page is @-mentioned/tagged
            (mention_kind = tagged_post).
          - Instagram: GET /{ig-user-id}/tags — media in which our IG business account is tagged
            (mention_kind = tagged_media). The IG user id is resolved from the linked Page
            (the Get-ImperionInstagramMedia hop) unless -IgUserId is given.

        Each row is flattened to the EXACT meta_mentions column set (front-end migration, FE
        #1365): platform, mention_id, mention_kind, permalink, message, author_id,
        author_username, author_name, created_time, raw. id / ingested_at have DB defaults and
        are omitted. UNIQUE (platform, mention_id) — the writer upserts ON CONFLICT
        (platform, mention_id). Returns rows; does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat (the Get-ImperionMetaPagePost precedent): the field lists
        follow Meta's published tagged/tags references; a field the token cannot read simply
        comes back absent and its flat column lands NULL — nothing is lost (full payload in
        `raw`). Verify against a live first run. Mention author/message bodies are third-party
        content — never logged.
    .PARAMETER PageId
        The Facebook Page id (collects its /tagged edge, and resolves the linked IG account
        for /tags unless -IgUserId is supplied).
    .PARAMETER IgUserId
        Instagram business-account (IG user) id override — skips the Page→IG hop.
    .PARAMETER Since
        Optional incremental lower bound (ISO-8601 or unix time, passed as the documented
        `since` filter). Omit for a full backfill.
    .PARAMETER Token
        Meta page token (or system-user token), sent as the bearer header. Defaults to the
        SecretStore resolution (Resolve-ImperionMetaToken, ADR-0013). Held in memory; never logged.
    .PARAMETER MaxPages
        Paging cap per edge forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionMetaMention -PageId $pageId | Set-ImperionMetaMentionToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $PageId,
        [string] $IgUserId,
        [string] $Since,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $Token = Resolve-ImperionMetaToken -Token $Token

    # ── Facebook: /{page-id}/tagged (posts our Page is tagged in) → mention_kind tagged_post ──
    # Fail-soft: a Facebook error must not stop the Instagram half (§1 per-source isolation).
    try {
        $fbFields = 'message,permalink_url,from,created_time'
        $fbUri = '{0}/tagged?fields={1}&limit=100' -f [uri]::EscapeDataString($PageId), $fbFields
        if ($Since) { $fbUri += '&since=' + [uri]::EscapeDataString($Since) }
        $tagged = @(Invoke-ImperionMetaRequest -Token $Token -Uri $fbUri -MaxPages $MaxPages)
        foreach ($post in $tagged) {
            ConvertTo-ImperionMetaMentionRow -Item $post -Platform 'facebook' -MentionKind 'tagged_post' `
                -PermalinkPath 'permalink_url' -MessagePath 'message' `
                -AuthorIdPath 'from.id' -AuthorNamePath 'from.name' -AuthorUsernamePath 'from.username' `
                -CreatedTimePath 'created_time'
        }
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'meta' -Message "Facebook mention collection failed (Page $PageId /tagged): $($_.Exception.Message)"
    }

    # ── Instagram: /{ig-user-id}/tags (media our IG account is tagged in) → mention_kind tagged_media ──
    try {
        if (-not $IgUserId) {
            $page = @(Invoke-ImperionMetaRequest -Token $Token `
                    -Uri ('{0}?fields=instagram_business_account' -f [uri]::EscapeDataString($PageId))) |
                Select-Object -First 1
            $IgUserId = if ($null -ne $page) {
                [string](Get-ImperionPropertyPath -InputObject $page -Path 'instagram_business_account.id')
            }
        }
        if (-not $IgUserId) {
            Write-ImperionLog -Level Warn -Source 'meta' -Message "Page $PageId has no linked instagram_business_account - skipping IG mentions."
        }
        else {
            $igFields = 'caption,permalink,username,owner,timestamp'
            $igUri = '{0}/tags?fields={1}&limit=100' -f [uri]::EscapeDataString($IgUserId), $igFields
            if ($Since) { $igUri += '&since=' + [uri]::EscapeDataString($Since) }
            $tags = @(Invoke-ImperionMetaRequest -Token $Token -Uri $igUri -MaxPages $MaxPages)
            foreach ($media in $tags) {
                ConvertTo-ImperionMetaMentionRow -Item $media -Platform 'instagram' -MentionKind 'tagged_media' `
                    -PermalinkPath 'permalink' -MessagePath 'caption' `
                    -AuthorIdPath 'owner.id' -AuthorNamePath 'username' -AuthorUsernamePath 'username' `
                    -CreatedTimePath 'timestamp'
            }
        }
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'meta' -Message "Instagram mention collection failed (IG $IgUserId /tags): $($_.Exception.Message)"
    }
}
