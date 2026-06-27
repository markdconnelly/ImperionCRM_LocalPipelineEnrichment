function Invoke-ImperionSocialEngagementMerge {
    <#
    .SYNOPSIS
        Merge Meta comment + mention bronze into the silver social_engagement inbound store (slice H, #357).
    .DESCRIPTION
        The bronze→silver merge for the Social Engagement inbound store (front-end Social
        plane epic #1338 / ADR-0124 decision 2; silver table + grants from front-end
        migration 0210), owned by this repo on the merge-co-locates-with-ingestion precedent
        (ADR-0026; the Meta 0075 / posture-merge pattern). Scope is COMMENTS on our posts (the
        facebook_comments + instagram_comments bronze) PLUS brand MENTIONS (the meta_mentions
        bronze, LP #391 / front-end #1365 — the deferred half now that the mention bronze exists),
        all collected by Invoke-ImperionSocialEngagementSync.

        Three idempotent, set-based steps — each INSERT is gated by ON CONFLICT (channel,
        external_id) DO NOTHING (the 0210 idempotency contract), so a re-run converges and
        never duplicates (CLAUDE.md §6):

          1. facebook_comments  → social_engagement (channel facebook,  kind comment)
          2. instagram_comments → social_engagement (channel instagram, kind comment)
          3. meta_mentions      → social_engagement (channel = platform, kind mention; source_url = permalink)

        Per the 0210 contract this merge lands ONLY the ingestion-owned columns: channel,
        external_id, kind, body, posted_at, the author_* fields, and source_url. It leaves
        contact_id / intent / assigned_agent_key NULL and status at its 'new' default — slice
        G (contact-link on match) and triage set those later. INSERT-only — never
        UPDATE/DELETE on silver. Bronze text timestamps are cast with a regex guard (the
        posture-merge pattern) so junk lands NULL, never throws.

        GRANT NOTE (verify before prod, see the PR): LP connects as the Postgres role
        `imperion-localpipeline` (config Db.Username). Migration 0210 grants social_engagement
        RW to `mgid-imperioncrmpipeline`, NOT to `imperion-localpipeline` — a grant gap this
        collector cannot fix here (schema/grants are front-end-owned, system CLAUDE.md §1). A
        front-end issue requests the missing INSERT/UPDATE grant; until it lands + applies, the
        prod write fails closed and the next run converges. Requires Initialize-ImperionContext.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionSocialEngagementMerge
    .EXAMPLE
        Invoke-ImperionSocialEngagementMerge -WhatIf   # show the step plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('meta engagement bronze (facebook_comments, instagram_comments, meta_mentions)', 'merge to social_engagement')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        $tally = [ordered]@{}

        # ── 1. facebook_comments → social_engagement (channel facebook, kind comment) ──
        # author_external_id/handle/display_name carry the commenter (third-party PII; the
        # 0210 OKF lawful-basis note covers it). source_url is left NULL for comments (the
        # column is the mention's source). posted_at: guarded created_time cast, collected_at
        # fallback.
        $tally['facebook_comments_to_engagement'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
INSERT INTO social_engagement (channel, external_id, kind, body, posted_at,
                               author_external_id, author_handle, author_display_name)
SELECT 'facebook'::social_channel, b.external_id, 'comment'::social_engagement_kind,
       b.message,
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END,
       b.from_id, b.from_name, b.from_name
  FROM facebook_comments b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
ON CONFLICT (channel, external_id) DO NOTHING
"@

        # ── 2. instagram_comments → social_engagement (channel instagram, kind comment) ─
        # IG comments expose `username` (handle) but not a display name; from_id is the
        # commenter's IG id. source_url left NULL (comment, not mention).
        $tally['instagram_comments_to_engagement'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
INSERT INTO social_engagement (channel, external_id, kind, body, posted_at,
                               author_external_id, author_handle, author_display_name)
SELECT 'instagram'::social_channel, b.external_id, 'comment'::social_engagement_kind,
       b.comment_text,
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END,
       b.from_id, b.username, b.username
  FROM instagram_comments b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
ON CONFLICT (channel, external_id) DO NOTHING
"@

        # ── 3. meta_mentions → social_engagement (kind mention; LP #391 / front-end #1365) ──
        # Brand mentions live on someone else's content, so source_url carries the mention's
        # permalink and on_social_post_channel_id stays NULL (left to its default — the column
        # is for comments on OUR posts). platform ('facebook'|'instagram') maps straight onto the
        # social_channel enum. meta_mentions.created_time is a real timestamptz column (not the
        # bronze text the comment tables carry), so it casts directly — but the same regex guard
        # is kept so a junk text value lands NULL instead of throwing. author_id/username/name map
        # to author_external_id/handle/display_name (third-party PII — OKF lawful-basis, ADR-0025).
        $tally['meta_mentions_to_engagement'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
INSERT INTO social_engagement (channel, external_id, kind, body, posted_at,
                               author_external_id, author_handle, author_display_name, source_url)
SELECT b.platform::social_channel, b.mention_id, 'mention'::social_engagement_kind,
       b.message,
       CASE WHEN b.created_time::text ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE NULL END,
       b.author_id, b.author_username, b.author_name, b.permalink
  FROM meta_mentions b
 WHERE b.mention_id <> ''   -- defense-in-depth vs envelope rows (#133)
ON CONFLICT (channel, external_id) DO NOTHING
"@

        $metrics = [ordered]@{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
        foreach ($key in $tally.Keys) { $metrics[$key] = $tally[$key] }
        Write-ImperionLog -Level Metric -Source 'meta' -Message 'Social engagement merge complete.' -Data ([hashtable]$metrics)

        return [pscustomobject]$tally
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
