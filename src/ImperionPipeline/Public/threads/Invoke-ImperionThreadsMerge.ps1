function Invoke-ImperionThreadsMerge {
    <#
    .SYNOPSIS
        Merge the threads bronze tables into silver: interaction (posts/replies/mentions) + social_metric (insights).
    .DESCRIPTION
        The bronze→silver merge for the `threads` source (LocalPipeline #356, front-end Threads
        epic #1334 / ADR-0125; grants from front-end migration 0208), owned by this repo on the
        merge-co-locates-with-ingestion precedent (ADR-0026; the Meta 0075 / posture-merge
        pattern). Idempotent, set-based steps — every INSERT is gated by NOT EXISTS / ON
        CONFLICT DO NOTHING, so a re-run converges and never duplicates (CLAUDE.md §6):

          1. threads_posts    → interaction (source threads, kind social_post,    outbound)
          2. threads_replies  → interaction (source threads, kind social_comment, direction by
             author: a reply authored by the root post's owner = outbound, else inbound)
          3. threads_mentions → interaction (source threads, kind mention,         inbound)
          4. threads_insights → social_metric (platform 'threads'; guarded numeric/timestamptz
             casts; ON CONFLICT DO NOTHING on the social_metric unique key)

        This mirrors the documented Threads silver mapping (front-end #1347; OKF concept files
        interaction.md + social_metric.md already carry the `threads` rows). v1 mentions are
        *of us*, not lead captures — there is NO lead_hook / lead_capture grant for threads (the
        FB-DM-only distinction, 0208). Bronze text timestamps are cast with regex guards so junk
        lands as the collected_at fallback, never throws. INSERT-only — never UPDATE/DELETE on
        silver (the 0208 grant posture). Requires Initialize-ImperionContext.

        This cmdlet is a thin **Merge Plan builder** (epic #429, ADR-0026): it assembles the
        declarative Global Plan — the four ordered, set-based INSERT steps — and hands it to
        Invoke-ImperionMergeByPlan, which owns the shared orchestration (connection lifecycle,
        ShouldProcess, tally, structured logging). The SQL below is unchanged from the
        hand-rolled version it replaces, so behaviour is byte-identical.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionThreadsMerge
    .EXAMPLE
        Invoke-ImperionThreadsMerge -WhatIf   # show the step plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    # Declarative steps, run in order. Each step is set-based and idempotent; the scaffold
    # owns connection lifecycle, ShouldProcess, tally, and logging.
    $steps = [System.Collections.Generic.List[hashtable]]::new()

    # ── 1–3. bronze → interaction ────────────────────────────────────────────
    # One INSERT…SELECT per (bronze table, kind); the NOT EXISTS gate keys on
    # (source, external_ref) — the merge's idempotency contract. occurred_at:
    # guarded created_time cast, collected_at fallback (loader-written ISO).
    $steps.Add(@{
            Name = 'threads_posts_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'threads'::interaction_source, 'social_post', left(b.text_content, 140), 'outbound'::interaction_direction,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'threads_user_id', b.threads_user_id, 'username', b.username, 'text', b.text_content,
           'media_type', b.media_type, 'permalink', b.permalink, 'shortcode', b.shortcode,
           'is_quote_post', b.is_quote_post, 'reply_audience', b.reply_audience),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM threads_posts b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'threads' AND i.external_ref = b.external_id)
"@
        })
    $steps.Add(@{
            Name = 'threads_replies_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'threads'::interaction_source, 'social_comment', left(b.text_content, 140),
       CASE WHEN b.threads_user_id IS NOT NULL AND b.threads_user_id = p.threads_user_id
            THEN 'outbound'::interaction_direction
            ELSE 'inbound'::interaction_direction END,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'root_post_external_id', b.root_post_external_id,
           'replied_to_external_id', b.replied_to_external_id,
           'threads_user_id', b.threads_user_id, 'username', b.username, 'text', b.text_content,
           'media_type', b.media_type, 'permalink', b.permalink, 'hide_status', b.hide_status),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM threads_replies b
  LEFT JOIN threads_posts p ON p.external_id = b.root_post_external_id
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'threads' AND i.external_ref = b.external_id)
"@
        })
    $steps.Add(@{
            Name = 'threads_mentions_to_interaction'
            Sql  = @"
INSERT INTO interaction (source, kind, subject, direction, external_ref, payload_bronze, normalized_silver, occurred_at)
SELECT 'threads'::interaction_source, 'mention', left(b.text_content, 140), 'inbound'::interaction_direction,
       b.external_id, b.raw_payload,
       jsonb_build_object(
           'mentioned_post_external_id', b.mentioned_post_external_id,
           'threads_user_id', b.threads_user_id, 'username', b.username,
           'text', b.text_content, 'permalink', b.permalink),
       CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM threads_mentions b
 WHERE b.external_id <> ''   -- defense-in-depth vs envelope rows
   AND NOT EXISTS (SELECT 1 FROM interaction i
                    WHERE i.source = 'threads' AND i.external_ref = b.external_id)
"@
        })

    # ── 4. threads_insights → social_metric ──────────────────────────────────
    # platform 'threads' (ADR-0124 D9 → BI hub, #135 name norm). Guarded numeric/
    # timestamptz casts (the meta_insights precedent); the social_metric unique key
    # (platform, entity_kind, entity_external_id, metric, period, captured_at) makes
    # the snapshot series naturally idempotent.
    $steps.Add(@{
            Name = 'social_metrics_merged'
            Sql  = @"
INSERT INTO social_metric (platform, entity_kind, entity_external_id, metric, period, value, captured_at)
SELECT 'threads', b.entity_kind, b.entity_external_id, b.metric, b.period,
       CASE WHEN b.value ~ '^-?\d+(\.\d+)?$' THEN b.value::numeric END,
       CASE WHEN b.end_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.end_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM threads_insights b
 WHERE b.entity_kind IS NOT NULL AND b.entity_external_id IS NOT NULL AND b.metric IS NOT NULL
   AND b.period IS NOT NULL  -- NULLs are distinct under the unique key: a NULL period would defeat ON CONFLICT and duplicate on re-run
ON CONFLICT (platform, entity_kind, entity_external_id, metric, period, captured_at) DO NOTHING
"@
        })

    $plan = @{
        Source = 'threads'
        Scope  = 'Global'
        Steps  = $steps
    }

    # One operation-level gate so -WhatIf is accepted and short-circuits cleanly (no
    # connection, no SQL) before delegating; the scaffold re-gates per step for real runs.
    if (-not $PSCmdlet.ShouldProcess('threads bronze (threads_posts, threads_replies, threads_mentions, threads_insights)', 'merge to silver')) { return }

    $result = Invoke-ImperionMergeByPlan -Plan $plan -Connection $Connection
    return [pscustomobject]$result.tally
}
