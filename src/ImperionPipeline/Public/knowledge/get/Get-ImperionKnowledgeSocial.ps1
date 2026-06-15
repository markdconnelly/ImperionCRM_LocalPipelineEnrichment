function Get-ImperionKnowledgeSocial {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every Facebook/Instagram social interaction.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009, issue #127). The
        social front is memory too: every FB/IG post, comment, and DM that the Meta merge
        (Invoke-ImperionMetaMerge, #126) lands in the silver `interaction` table becomes
        its own knowledge object so the agent can answer "what did people say to us on
        social" from per-interaction retrieval. Composes the three social `kind`s
        (social_post, social_comment, dm) for the two social `source`s (facebook,
        instagram); the non-social interaction sources are left to other composers.

        The human-readable body draws on the normalized_silver jsonb the merge wrote
        (author name/handle, message/caption/comment text, permalink, engagement counts)
        rather than re-reading bronze — silver is the contract. Where the interaction
        resolves to a known contact via contact_social_identity (the DM-sender lead path),
        the contact's name is surfaced so the object joins the CRM picture.

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): this declares the SQL + compose block; the spine owns the scaffold. Output
        rows are flat PSCustomObjects in the knowledge_object shape (entity_type='social',
        entity_ref = the interaction id). Read-only; pass -Connection to reuse one DB
        connection across the knowledge sync. Idempotency is the spine's content hash over
        title+body — an unchanged interaction never re-composes and never re-embeds (§7).
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant (Imperion's own social data).
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeSocial | Set-ImperionKnowledgeObject
    .EXAMPLE
        Invoke-ImperionKnowledgeSync -EntityType social -Vectorize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    Invoke-ImperionKnowledgeCompose -EntityType 'social' -Connection $Connection -TenantId $TenantId `
        -LogLabel 'social interactions' -CountName 'social interactions' `
        -EmptyMessage 'knowledge social: no facebook/instagram interactions in silver.' `
        -Query @'
SELECT i.id::text AS id, i.source::text AS source, i.kind, i.direction::text AS direction,
       i.subject, i.occurred_at,
       i.normalized_silver->>'message'      AS message,
       i.normalized_silver->>'caption'      AS caption,
       i.normalized_silver->>'comment_text' AS comment_text,
       i.normalized_silver->>'from_name'    AS from_name,
       i.normalized_silver->>'username'     AS username,
       i.normalized_silver->>'permalink'     AS permalink,
       i.normalized_silver->>'permalink_url' AS permalink_url,
       i.normalized_silver->>'like_count'     AS like_count,
       i.normalized_silver->>'comment_count'  AS comment_count,
       i.normalized_silver->>'comments_count' AS comments_count,
       i.normalized_silver->>'reaction_count' AS reaction_count,
       i.normalized_silver->>'share_count'    AS share_count,
       c.full_name AS contact_name
  FROM interaction i
  LEFT JOIN contact_social_identity csi
         ON csi.platform = i.source::text
        AND csi.external_id = i.normalized_silver->>'from_id'
  LEFT JOIN contact c ON c.id = csi.contact_id
 WHERE i.source IN ('facebook', 'instagram')
   AND i.kind IN ('social_post', 'social_comment', 'dm')
 ORDER BY i.occurred_at DESC NULLS LAST
'@ -Compose {
        param($interaction)

        $platform = if ($interaction.source -eq 'instagram') { 'Instagram' } else { 'Facebook' }
        $kindLabel = switch ($interaction.kind) {
            'social_post'    { 'post' }
            'social_comment' { 'comment' }
            'dm'             { 'direct message' }
            default          { $interaction.kind }
        }
        # Text body: comment text > caption (posts) > message (posts/DMs) > subject.
        $text = @($interaction.comment_text, $interaction.caption, $interaction.message, $interaction.subject) |
            Where-Object { $_ } | Select-Object -First 1
        $author = @($interaction.from_name, $interaction.username, $interaction.contact_name) |
            Where-Object { $_ } | Select-Object -First 1

        $titleText = if ($text) { ($text -replace '\s+', ' ').Trim() } else { '' }
        if ($titleText.Length -gt 80) { $titleText = $titleText.Substring(0, 77).TrimEnd() + '...' }
        $title = if ($titleText) { "$platform ${kindLabel}: $titleText" } else { "$platform $kindLabel" }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("$platform $kindLabel ($($interaction.direction))")
        if ($author) { $lines.Add("From: $author") }
        if ($interaction.contact_name -and $interaction.contact_name -ne $author) {
            $lines.Add("Contact: $($interaction.contact_name)")
        }
        if ($interaction.occurred_at) { $lines.Add("When: $($interaction.occurred_at)") }

        $permalink = @($interaction.permalink, $interaction.permalink_url) | Where-Object { $_ } | Select-Object -First 1
        if ($permalink) { $lines.Add("Link: $permalink") }

        $engagement = @(
            if ($interaction.like_count)     { "likes: $($interaction.like_count)" }
            if ($interaction.reaction_count) { "reactions: $($interaction.reaction_count)" }
            $replyCount = @($interaction.comment_count, $interaction.comments_count) | Where-Object { $_ } | Select-Object -First 1
            if ($replyCount)                 { "comments: $replyCount" }
            if ($interaction.share_count)    { "shares: $($interaction.share_count)" }
        )
        if ($engagement) { $lines.Add(($engagement -join ' · ')) }

        if ($text) { $lines.Add(''); $lines.Add($text) }

        [pscustomobject]@{
            entity_ref = [string]$interaction.id
            title      = $title
            body       = ($lines -join "`n").Trim()
            source     = $interaction.source
            metadata   = @{
                platform  = $interaction.source
                kind      = $interaction.kind
                direction = $interaction.direction
                author    = $author
                contact   = $interaction.contact_name
                permalink = $permalink
            }
        }
    }
}
