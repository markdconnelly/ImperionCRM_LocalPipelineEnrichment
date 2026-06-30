function Invoke-ImperionMetaMerge {
    <#
    .SYNOPSIS
        Merge the meta bronze tables into silver: interaction, lead capture (DM senders), social_metric, and client_communication (social_dm for DMs with an onboarded client).
    .DESCRIPTION
        The bronze→silver merge for the Meta source (issue #126; IG DMs LocalPipeline #361),
        owned by this repo on the posture-merge precedent (ADR-0010 / ADR-0013; grants from
        front-end migrations 0075 + 0206). Idempotent, set-based steps — every INSERT is
        gated by NOT EXISTS or ON CONFLICT DO NOTHING, so a re-run converges and never
        duplicates (CLAUDE.md §6):

          1. facebook_posts      → interaction (source facebook,  kind social_post,    outbound)
          2. facebook_comments   → interaction (source facebook,  kind social_comment, inbound)
          3. instagram_media     → interaction (source instagram, kind social_post,    outbound)
             instagram_comments  → interaction (source instagram, kind social_comment, inbound)
          4. facebook_messages   → interaction (source facebook,  kind dm; direction by
             from_id = page_id → outbound, else inbound)
             instagram_messages  → interaction (source instagram, kind dm; direction by
             from_id = ig_user_id → outbound, else inbound) [0206, LocalPipeline #361]
          5. Lead capture (per channel): ensure ONE lead_hook — kind facebook_dm
             ('Facebook page inbox') and kind instagram_dm ('Instagram direct messages');
             for each DISTINCT inbound DM sender, resolve the contact via
             contact_social_identity (platform facebook / instagram) or create a minimal
             contact + identity, then insert ONE lead_capture_event per sender (matched on
             hook + payload_bronze->>'from_id'). DM SENDERS ARE LEADS; commenters stay
             timeline-only (the 0075 / 0207 contract).
          6. meta_insights → social_metric (platform facebook for entity_kind page,
             else instagram; guarded numeric/timestamptz casts; ON CONFLICT DO NOTHING
             on the 0075 unique key).
          7-8. facebook_messages / instagram_messages → client_communication
             (channel social_dm; source_system meta_messenger / instagram_dm; #383,
             front-end #1370 / docs/database/social-dm-foldin.md). The SECOND, FILTERED
             projection of the DM bronze (alongside step 4's unfiltered interaction):
             retained ONLY when the non-Imperion counterparty resolves to a LINKED client
             contact via contact_social_identity (INNER JOIN LATERAL = the filter gate; no
             account_domain path — handles carry no email domain). PII-minimal: subject
             NULL, snippet = truncated message preview, NEVER the body (ADR-0126). direction
             by sender (inbound = client→Imperion). Idempotent upsert on the 0211 key
             (channel, source_system, external_id) with content_hash change detection.

        Bronze text timestamps are cast with regex guards (the posture-merge pattern) so
        junk lands as the collected_at fallback, never throws. INSERT-only — never
        UPDATE/DELETE on silver (the 0075 grant posture). Requires
        Initialize-ImperionContext.

        This cmdlet is a thin **Merge Plan builder** (epic #429, ADR-0026): it assembles
        the declarative Global Plan — the ordered, set-based SQL steps — and hands it to
        Invoke-ImperionMergeByPlan, which owns the shared orchestration (connection
        lifecycle, ShouldProcess, tally, structured logging). The SQL below is unchanged
        from the hand-rolled version it replaces, so behaviour is byte-identical.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionMetaMerge
    .EXAMPLE
        Invoke-ImperionMetaMerge -WhatIf   # show the step plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    # One operation-level gate so -WhatIf short-circuits cleanly with no connection and no
    # SQL, before the scaffold is built or called.
    if (-not $PSCmdlet.ShouldProcess('meta bronze (facebook_*, instagram_*, meta_insights)', 'merge to silver')) { return }

    $steps = [System.Collections.Generic.List[hashtable]]::new()

    # ── 1–4. bronze → interaction ────────────────────────────────────────────
    # One INSERT…SELECT per (bronze table, kind); the NOT EXISTS gate keys on
    # (source, external_ref) — the merge's idempotency contract. occurred_at:
    # guarded created_time cast, collected_at fallback (loader-written ISO).
    $steps.Add(@{
            Name = 'facebook_posts_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'facebook'::interaction_source, 'social_post', left(b.message, 140), 'outbound'::interaction_direction,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'page_id', b.page_id, 'message', b.message, 'story', b.story,
           'status_type', b.status_type, 'permalink_url', b.permalink_url,
           'comment_count', b.comment_count, 'reaction_count', b.reaction_count,
           'share_count', b.share_count),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM facebook_posts b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'facebook' AND i.external_ref = b.external_id)
"@
        })
    $steps.Add(@{
            Name = 'facebook_comments_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'facebook'::interaction_source, 'social_comment', left(b.message, 140), 'inbound'::interaction_direction,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'post_external_id', b.post_external_id, 'parent_comment_id', b.parent_comment_id,
           'message', b.message, 'from_id', b.from_id, 'from_name', b.from_name,
           'like_count', b.like_count, 'comment_count', b.comment_count),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM facebook_comments b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'facebook' AND i.external_ref = b.external_id)
"@
        })
    $steps.Add(@{
            Name = 'instagram_media_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'instagram'::interaction_source, 'social_post', left(b.caption, 140), 'outbound'::interaction_direction,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'ig_user_id', b.ig_user_id, 'ig_username', b.ig_username, 'caption', b.caption,
           'media_type', b.media_type, 'media_product_type', b.media_product_type,
           'permalink', b.permalink, 'like_count', b.like_count, 'comments_count', b.comments_count),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM instagram_media b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'instagram' AND i.external_ref = b.external_id)
"@
        })
    $steps.Add(@{
            Name = 'instagram_comments_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'instagram'::interaction_source, 'social_comment', left(b.comment_text, 140), 'inbound'::interaction_direction,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'media_external_id', b.media_external_id, 'parent_comment_id', b.parent_comment_id,
           'comment_text', b.comment_text, 'username', b.username, 'from_id', b.from_id,
           'like_count', b.like_count),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM instagram_comments b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'instagram' AND i.external_ref = b.external_id)
"@
        })
    $steps.Add(@{
            Name = 'facebook_messages_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'facebook'::interaction_source, 'dm', left(b.message, 140),
       CASE WHEN b.from_id = b.page_id THEN 'outbound'::interaction_direction
            ELSE 'inbound'::interaction_direction END,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'conversation_id', b.conversation_id, 'page_id', b.page_id, 'message', b.message,
           'from_id', b.from_id, 'from_name', b.from_name, 'to_id', b.to_id, 'to_name', b.to_name),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM facebook_messages b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'facebook' AND i.external_ref = b.external_id)
"@
        })
    $steps.Add(@{
            Name = 'instagram_messages_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'instagram'::interaction_source, 'dm', left(b.message, 140),
       CASE WHEN b.from_id = b.ig_user_id THEN 'outbound'::interaction_direction
            ELSE 'inbound'::interaction_direction END,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'conversation_id', b.conversation_id, 'ig_user_id', b.ig_user_id, 'message', b.message,
           'from_id', b.from_id, 'from_username', b.from_username, 'to_id', b.to_id, 'to_username', b.to_username),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM instagram_messages b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'instagram' AND i.external_ref = b.external_id)
"@
        })

    # ── 5. DM senders → leads ────────────────────────────────────────────────
    # 5a. Exactly one hook row for the page inbox, keyed (kind, name).
    $steps.Add(@{
            Name = 'lead_hook_ensured'
            Sql  = @"
INSERT INTO lead_hook (name, kind, config)
SELECT 'Facebook page inbox', 'facebook_dm'::lead_hook_kind,
       jsonb_build_object('page_id', (SELECT page_id FROM facebook_messages
                                       WHERE page_id IS NOT NULL LIMIT 1))
 WHERE NOT EXISTS (SELECT 1 FROM lead_hook
                    WHERE kind = 'facebook_dm' AND name = 'Facebook page inbox')
"@
        })

    # 5b. Minimal contact + facebook social identity for senders not yet known.
    # The new contact carries the sender's from_id in attribution so the identity
    # insert can join RETURNING rows back to their sender deterministically.
    $steps.Add(@{
            Name = 'contacts_created'
            Sql  = @"
WITH sender AS (
    SELECT DISTINCT ON (from_id) from_id, from_name
      FROM facebook_messages
     WHERE from_id IS NOT NULL AND page_id IS NOT NULL AND from_id <> page_id
     ORDER BY from_id, created_time
), missing AS (
    SELECT s.* FROM sender s
     WHERE NOT EXISTS (SELECT 1 FROM contact_social_identity csi
                        WHERE csi.platform = 'facebook' AND csi.external_id = s.from_id)
), new_contact AS (
    INSERT INTO contact (full_name, attribution)
    SELECT COALESCE(NULLIF(m.from_name, ''), 'Facebook user ' || m.from_id),
           jsonb_build_object('source', 'facebook_dm', 'facebook_from_id', m.from_id)
      FROM missing m
    RETURNING id, attribution->>'facebook_from_id' AS from_id
)
INSERT INTO contact_social_identity (contact_id, platform, external_id, raw)
SELECT nc.id, 'facebook', nc.from_id,
       jsonb_build_object('from_id', m.from_id, 'from_name', m.from_name)
  FROM new_contact nc
  JOIN missing m ON m.from_id = nc.from_id
"@
        })

    # 5c. ONE lead_capture_event per sender (not per message): keyed on
    # (hook, payload_bronze->>'from_id'); payload carries the FIRST message.
    $steps.Add(@{
            Name = 'lead_captures_created'
            Sql  = @"
WITH sender AS (
    SELECT DISTINCT ON (from_id) from_id, from_name, conversation_id, message, created_time
      FROM facebook_messages
     WHERE from_id IS NOT NULL AND page_id IS NOT NULL AND from_id <> page_id
     ORDER BY from_id, created_time
), hook AS (
    SELECT id FROM lead_hook
     WHERE kind = 'facebook_dm' AND name = 'Facebook page inbox'
     LIMIT 1
)
INSERT INTO lead_capture_event (hook_id, payload_bronze, contact_id, status, received_at)
SELECT h.id,
       jsonb_build_object(
           'from_id', s.from_id, 'from_name', s.from_name,
           'conversation_id', s.conversation_id,
           'first_message', s.message, 'first_message_at', s.created_time),
       csi.contact_id, 'new',
       CASE WHEN s.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN s.created_time::timestamptz
            ELSE now() END
  FROM sender s
 CROSS JOIN hook h
  LEFT JOIN LATERAL (
        SELECT contact_id FROM contact_social_identity
         WHERE platform = 'facebook' AND external_id = s.from_id
         LIMIT 1) csi ON true
 WHERE NOT EXISTS (SELECT 1 FROM lead_capture_event e
                    WHERE e.hook_id = h.id
                      AND e.payload_bronze->>'from_id' = s.from_id)
"@
        })

    # ── 5d-5f. IG DM senders → leads ─────────────────────────────────────────
    # The IG twin of 5a-5c (front-end migration 0207): own hook kind instagram_dm,
    # platform 'instagram' on contact_social_identity, sender = from_id <> ig_user_id.
    # IG participants carry from_username (not from_name).
    # 5d. Exactly one hook row for the IG inbox.
    $steps.Add(@{
            Name = 'ig_lead_hook_ensured'
            Sql  = @"
INSERT INTO lead_hook (name, kind, config)
SELECT 'Instagram direct messages', 'instagram_dm'::lead_hook_kind,
       jsonb_build_object('ig_user_id', (SELECT ig_user_id FROM instagram_messages
                                          WHERE ig_user_id IS NOT NULL LIMIT 1))
 WHERE NOT EXISTS (SELECT 1 FROM lead_hook
                    WHERE kind = 'instagram_dm' AND name = 'Instagram direct messages')
"@
        })

    # 5e. Minimal contact + instagram social identity for senders not yet known.
    $steps.Add(@{
            Name = 'ig_contacts_created'
            Sql  = @"
WITH sender AS (
    SELECT DISTINCT ON (from_id) from_id, from_username
      FROM instagram_messages
     WHERE from_id IS NOT NULL AND ig_user_id IS NOT NULL AND from_id <> ig_user_id
     ORDER BY from_id, created_time
), missing AS (
    SELECT s.* FROM sender s
     WHERE NOT EXISTS (SELECT 1 FROM contact_social_identity csi
                        WHERE csi.platform = 'instagram' AND csi.external_id = s.from_id)
), new_contact AS (
    INSERT INTO contact (full_name, attribution)
    SELECT COALESCE(NULLIF(m.from_username, ''), 'Instagram user ' || m.from_id),
           jsonb_build_object('source', 'instagram_dm', 'instagram_from_id', m.from_id)
      FROM missing m
    RETURNING id, attribution->>'instagram_from_id' AS from_id
)
INSERT INTO contact_social_identity (contact_id, platform, external_id, raw)
SELECT nc.id, 'instagram', nc.from_id,
       jsonb_build_object('from_id', m.from_id, 'from_username', m.from_username)
  FROM new_contact nc
  JOIN missing m ON m.from_id = nc.from_id
"@
        })

    # 5f. ONE lead_capture_event per IG DM sender, keyed (hook, payload from_id).
    $steps.Add(@{
            Name = 'ig_lead_captures_created'
            Sql  = @"
WITH sender AS (
    SELECT DISTINCT ON (from_id) from_id, from_username, conversation_id, message, created_time
      FROM instagram_messages
     WHERE from_id IS NOT NULL AND ig_user_id IS NOT NULL AND from_id <> ig_user_id
     ORDER BY from_id, created_time
), hook AS (
    SELECT id FROM lead_hook
     WHERE kind = 'instagram_dm' AND name = 'Instagram direct messages'
     LIMIT 1
)
INSERT INTO lead_capture_event (hook_id, payload_bronze, contact_id, status, received_at)
SELECT h.id,
       jsonb_build_object(
           'from_id', s.from_id, 'from_username', s.from_username,
           'conversation_id', s.conversation_id,
           'first_message', s.message, 'first_message_at', s.created_time),
       csi.contact_id, 'new',
       CASE WHEN s.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN s.created_time::timestamptz
            ELSE now() END
  FROM sender s
 CROSS JOIN hook h
  LEFT JOIN LATERAL (
        SELECT contact_id FROM contact_social_identity
         WHERE platform = 'instagram' AND external_id = s.from_id
         LIMIT 1) csi ON true
 WHERE NOT EXISTS (SELECT 1 FROM lead_capture_event e
                    WHERE e.hook_id = h.id
                      AND e.payload_bronze->>'from_id' = s.from_id)
"@
        })

    # ── 6. meta_insights → social_metric ─────────────────────────────────────
    # Guarded numeric/timestamptz casts (posture-merge pattern); the 0075 unique
    # key (platform, entity_kind, entity_external_id, metric, period, captured_at)
    # makes the snapshot series naturally idempotent.
    $steps.Add(@{
            Name = 'social_metrics_merged'
            Sql  = @"
INSERT INTO social_metric (platform, entity_kind, entity_external_id, metric, period, value, captured_at)
SELECT CASE WHEN b.entity_kind = 'page' THEN 'facebook' ELSE 'instagram' END,
       b.entity_kind, b.entity_external_id, b.metric, b.period,
       CASE WHEN b.value ~ '^-?\d+(\.\d+)?$' THEN b.value::numeric END,
       CASE WHEN b.end_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.end_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM meta_insights b
 WHERE b.entity_kind IS NOT NULL AND b.entity_external_id IS NOT NULL AND b.metric IS NOT NULL
   AND b.period IS NOT NULL  -- NULLs are distinct under the unique key: a NULL period would defeat ON CONFLICT and duplicate on re-run
ON CONFLICT (platform, entity_kind, entity_external_id, metric, period, captured_at) DO NOTHING
"@
        })

    # ── 7-8. DMs with an onboarded client → client_communication (social_dm) ──────
    # The SECOND, filtered projection of the DM bronze (#383, front-end #1370 /
    # docs/database/social-dm-foldin.md; silver client_communication 0211, ADR-0126).
    # A DM is retained ONLY when its non-Imperion counterparty resolves to a LINKED
    # client contact via contact_social_identity (the table steps 5b/5e populate) —
    # the INNER JOIN LATERAL is the filter gate, so prospect/public DMs (no linked
    # contact) stay interaction/lead_capture-only and never enter the client-comms
    # ledger. No account_domain path (handles carry no email domain). PII-minimal:
    # subject NULL, snippet = truncated message preview, NEVER the full body
    # (ADR-0126 privacy posture; the full text stays in interaction / bronze).
    # direction by sender (inbound = client→Imperion). Idempotent upsert on the 0211
    # key (channel, source_system, external_id) with content_hash change detection.

    # 7. facebook_messages → client_communication (channel social_dm, source meta_messenger)
    $steps.Add(@{
            Name = 'fb_dm_to_client_communication'
            Sql  = @"
INSERT INTO client_communication
  (account_id, contact_id, channel, direction, client_participants, imperion_participants,
   subject, snippet, occurred_at, source_system, external_id, thread_ref, content_hash, data_class)
SELECT link.account_id, link.contact_id, 'social_dm'::client_communication_channel,
       CASE WHEN b.from_id = b.page_id THEN 'outbound'::client_communication_direction
            ELSE 'inbound'::client_communication_direction END,
       ARRAY[ coalesce(NULLIF(CASE WHEN b.from_id = b.page_id THEN b.to_name ELSE b.from_name END, ''),
                       CASE WHEN b.from_id = b.page_id THEN b.to_id ELSE b.from_id END) ],
       ARRAY[ b.page_id ],
       NULL, left(b.message, 280),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END,
       'meta_messenger', b.external_id, b.conversation_id, b.content_hash, 'client_pii'
  FROM facebook_messages b
  JOIN LATERAL (
        SELECT c.account_id, c.id AS contact_id
          FROM contact_social_identity csi
          JOIN contact c ON c.id = csi.contact_id
         WHERE csi.platform = 'facebook' AND c.account_id IS NOT NULL
           AND csi.external_id = CASE WHEN b.from_id = b.page_id THEN b.to_id ELSE b.from_id END
         LIMIT 1) link ON true
 WHERE b.external_id <> '' AND b.page_id IS NOT NULL   -- defense-in-depth vs envelope rows (#133)
ON CONFLICT (channel, source_system, external_id) DO UPDATE SET
    account_id            = EXCLUDED.account_id,
    contact_id            = EXCLUDED.contact_id,
    direction             = EXCLUDED.direction,
    client_participants   = EXCLUDED.client_participants,
    imperion_participants = EXCLUDED.imperion_participants,
    snippet               = EXCLUDED.snippet,
    occurred_at           = EXCLUDED.occurred_at,
    thread_ref            = EXCLUDED.thread_ref,
    content_hash          = EXCLUDED.content_hash
  WHERE client_communication.content_hash IS DISTINCT FROM EXCLUDED.content_hash
"@
        })

    # 8. instagram_messages → client_communication (channel social_dm, source instagram_dm)
    $steps.Add(@{
            Name = 'ig_dm_to_client_communication'
            Sql  = @"
INSERT INTO client_communication
  (account_id, contact_id, channel, direction, client_participants, imperion_participants,
   subject, snippet, occurred_at, source_system, external_id, thread_ref, content_hash, data_class)
SELECT link.account_id, link.contact_id, 'social_dm'::client_communication_channel,
       CASE WHEN b.from_id = b.ig_user_id THEN 'outbound'::client_communication_direction
            ELSE 'inbound'::client_communication_direction END,
       ARRAY[ coalesce(NULLIF(CASE WHEN b.from_id = b.ig_user_id THEN b.to_username ELSE b.from_username END, ''),
                       CASE WHEN b.from_id = b.ig_user_id THEN b.to_id ELSE b.from_id END) ],
       ARRAY[ b.ig_user_id ],
       NULL, left(b.message, 280),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END,
       'instagram_dm', b.external_id, b.conversation_id, b.content_hash, 'client_pii'
  FROM instagram_messages b
  JOIN LATERAL (
        SELECT c.account_id, c.id AS contact_id
          FROM contact_social_identity csi
          JOIN contact c ON c.id = csi.contact_id
         WHERE csi.platform = 'instagram' AND c.account_id IS NOT NULL
           AND csi.external_id = CASE WHEN b.from_id = b.ig_user_id THEN b.to_id ELSE b.from_id END
         LIMIT 1) link ON true
 WHERE b.external_id <> '' AND b.ig_user_id IS NOT NULL   -- defense-in-depth vs envelope rows (#133)
ON CONFLICT (channel, source_system, external_id) DO UPDATE SET
    account_id            = EXCLUDED.account_id,
    contact_id            = EXCLUDED.contact_id,
    direction             = EXCLUDED.direction,
    client_participants   = EXCLUDED.client_participants,
    imperion_participants = EXCLUDED.imperion_participants,
    snippet               = EXCLUDED.snippet,
    occurred_at           = EXCLUDED.occurred_at,
    thread_ref            = EXCLUDED.thread_ref,
    content_hash          = EXCLUDED.content_hash
  WHERE client_communication.content_hash IS DISTINCT FROM EXCLUDED.content_hash
"@
        })

    $plan = @{
        Source = 'meta'
        Scope  = 'Global'
        Steps  = $steps
    }

    $result = Invoke-ImperionMergeByPlan -Plan $plan -Connection $Connection
    return [pscustomobject]$result.tally
}
