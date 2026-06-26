function Get-ImperionSocialMetricCanonSql {
    <#
    .SYNOPSIS
        The canonical social-metric-name normalization SQL fragment (#135), shared across merges.
    .DESCRIPTION
        Module-internal single source of truth for the stable, network-agnostic metric
        vocabulary that resolves front-end issue #135 (raw insight metric names are unstable
        across networks and across Meta API versions). Every social_metric merge maps each
        network's raw metric name onto ONE canonical name at SILVER (bronze stays lossless —
        the raw name survives in meta_insights / raw_payload), so the BI hub and the agents
        read one consistent vocabulary regardless of which network or API version produced it.

        Returns a SQL `CASE … END` expression that maps a raw metric column to its canonical
        name; a raw name with no mapping passes through unchanged (lower-cased) so a new Meta
        metric is never dropped — it just lands un-normalized until a mapping is added here.

        Canonical vocabulary (network-agnostic; the left column is what lands in
        social_metric.metric):

          impressions     ← page_impressions, page_impressions_unique, impressions,
                            post_impressions, post_impressions_unique
          reach           ← page_reach, reach, page_impressions_organic_unique
          engagement      ← page_post_engagements, post_engagements, post_clicks,
                            accounts_engaged, total_interactions, likes (engagement proxies)
          profile_views   ← profile_views, page_views_total
          follower_count  ← followers_count, page_fans, follower_count
          video_views     ← post_video_views, video_views, plays
          saved           ← saved
          shares          ← shares, post_shares
          comments        ← comments, post_comments
          spend           ← spend                              (paid / ad insights)
          clicks          ← clicks, inline_link_clicks         (paid / ad insights)
          ctr             ← ctr                                (paid / ad insights)
          cpc             ← cpc                                (paid / ad insights)
          cpm             ← cpm                                (paid / ad insights)
          frequency       ← frequency                          (paid / ad insights)

        The mapping is intentionally additive and conservative: only well-understood
        synonyms collapse; ambiguous metrics pass through verbatim rather than guess.
    .PARAMETER Column
        The raw-metric SQL column reference to normalize (e.g. 'b.metric'). Defaults to
        'b.metric' (the meta_insights / *_insights bronze column name).
    .EXAMPLE
        $canon = Get-ImperionSocialMetricCanonSql -Column 'b.metric'
        # → "CASE lower(b.metric) WHEN 'page_impressions' THEN 'impressions' … ELSE lower(b.metric) END"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Column = 'b.metric'
    )

    # canonical → the raw names that collapse onto it (#135 vocabulary).
    $canonMap = [ordered]@{
        impressions    = @('page_impressions', 'page_impressions_unique', 'impressions', 'post_impressions', 'post_impressions_unique')
        reach          = @('page_reach', 'reach', 'page_impressions_organic_unique')
        engagement     = @('page_post_engagements', 'post_engagements', 'post_clicks', 'accounts_engaged', 'total_interactions')
        profile_views  = @('profile_views', 'page_views_total')
        follower_count = @('followers_count', 'page_fans', 'follower_count')
        video_views    = @('post_video_views', 'video_views', 'plays')
        saved          = @('saved')
        shares         = @('shares', 'post_shares')
        comments       = @('comments', 'post_comments')
        spend          = @('spend')
        clicks         = @('clicks', 'inline_link_clicks')
        ctr            = @('ctr')
        cpc            = @('cpc')
        cpm            = @('cpm')
        frequency      = @('frequency')
    }

    $whenClauses = foreach ($canonical in $canonMap.Keys) {
        foreach ($raw in $canonMap[$canonical]) {
            "    WHEN '$raw' THEN '$canonical'"
        }
    }

    # lower() both the subject and (implicitly) the literals so casing never splits a series.
    "CASE lower($Column)`n$($whenClauses -join "`n")`n    ELSE lower($Column) END"
}
