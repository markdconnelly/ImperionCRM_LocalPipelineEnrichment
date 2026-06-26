function Invoke-ImperionSocialMetricMerge {
    <#
    .SYNOPSIS
        Merge meta_insights bronze into silver social_metric with NORMALIZED metric names (slice H, #357 / #135).
    .DESCRIPTION
        The bronze→silver merge for Social Metric time-series snapshots (front-end Social plane
        epic #1338 / ADR-0124; silver social_metric from front-end migration 0075), owned by
        this repo on the merge-co-locates-with-ingestion precedent (ADR-0026). Covers ALL Meta
        insight entity kinds landed in the meta_insights bronze:

          • organic page / ig_user insights  (Get-ImperionMetaInsight,     existing)
          • per-POST / per-MEDIA insights      (Get-ImperionMetaPostInsight, slice H)
          • per-AD / CAMPAIGN ad insights      (Get-ImperionMetaAdInsight,   slice H)

        all of which write the same meta_insights envelope (entity_kind, entity_external_id,
        metric, period, end_time, value). This single merge resolves front-end issue #135 by
        NORMALIZING each raw Meta metric name onto the canonical, network-agnostic vocabulary
        (Get-ImperionSocialMetricCanonSql) at SILVER — bronze keeps the raw name losslessly.
        The BI hub and the agents then read one stable vocabulary regardless of network or API
        version.

        platform is derived from entity_kind:
          page                              → 'facebook'
          ig_user | media                   → 'instagram'
          post                              → 'facebook'   (FB Page posts)
          ad | campaign | adset | adaccount → 'meta_ads'   (paid plane; one platform label)

        One idempotent, set-based INSERT … SELECT gated by ON CONFLICT (platform, entity_kind,
        entity_external_id, metric, period, captured_at) DO NOTHING (the 0075 unique key) — a
        re-run converges and never duplicates (CLAUDE.md §6). Guarded numeric/timestamptz casts
        (the posture-merge pattern) so junk text lands NULL, never throws. period IS NOT NULL is
        required (a NULL period is distinct under the unique key and would defeat ON CONFLICT,
        duplicating on re-run). INSERT-only — never UPDATE/DELETE on silver. The
        `imperion-localpipeline` role already holds social_metric INSERT (migration 0075).
        Requires Initialize-ImperionContext.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionSocialMetricMerge
    .EXAMPLE
        Invoke-ImperionSocialMetricMerge -WhatIf   # show the step plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('meta_insights (organic + post + ad)', 'merge to social_metric (normalized names)')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        $tally = [ordered]@{}
        $canonSql = Get-ImperionSocialMetricCanonSql -Column 'b.metric'

        # platform from entity_kind: organic page=facebook, ig_user/media=instagram, FB post=
        # facebook, paid (ad/campaign/adset/adaccount)=meta_ads. captured_at from the guarded
        # end_time cast (collected_at fallback). metric NORMALIZED via the shared canon SQL (#135).
        $tally['social_metrics_merged'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
INSERT INTO social_metric (platform, entity_kind, entity_external_id, metric, period, value, captured_at)
SELECT CASE
           WHEN b.entity_kind = 'page' THEN 'facebook'
           WHEN b.entity_kind IN ('ig_user', 'media') THEN 'instagram'
           WHEN b.entity_kind = 'post' THEN 'facebook'
           WHEN b.entity_kind IN ('ad', 'campaign', 'adset', 'adaccount') THEN 'meta_ads'
           ELSE 'meta'
       END,
       b.entity_kind, b.entity_external_id,
       $canonSql,
       b.period,
       CASE WHEN b.value ~ '^-?\d+(\.\d+)?$' THEN b.value::numeric END,
       CASE WHEN b.end_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.end_time::timestamptz
            ELSE b.collected_at::timestamptz END
  FROM meta_insights b
 WHERE b.entity_kind IS NOT NULL AND b.entity_external_id IS NOT NULL AND b.metric IS NOT NULL
   AND b.period IS NOT NULL  -- NULLs are distinct under the unique key: a NULL period would defeat ON CONFLICT and duplicate on re-run
ON CONFLICT (platform, entity_kind, entity_external_id, metric, period, captured_at) DO NOTHING
"@

        $metrics = [ordered]@{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
        foreach ($key in $tally.Keys) { $metrics[$key] = $tally[$key] }
        Write-ImperionLog -Level Metric -Source 'meta' -Message 'Social metric merge complete.' -Data ([hashtable]$metrics)

        return [pscustomobject]$tally
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
