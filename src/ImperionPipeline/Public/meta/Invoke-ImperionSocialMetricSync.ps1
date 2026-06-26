function Invoke-ImperionSocialMetricSync {
    <#
    .SYNOPSIS
        Collect Meta post + ad insight snapshots into bronze, then merge to silver social_metric (normalized names).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) for slice
        H of the front-end Social plane (#357; epic #1338 / ADR-0124). Promotes
        scheduled-tasks/meta/metrics.task.ps1. Hops to the Page token once (#133), collects
        per-post and per-media insights (Get-ImperionMetaPostInsight) and — when an ad account is
        configured — paid ad + campaign insights (Get-ImperionMetaAdInsight) into the 0075
        meta_insights bronze, then runs Invoke-ImperionSocialMetricMerge (meta_insights → silver
        social_metric with the canonical metric-name normalization that resolves front-end issue
        #135; merge co-locates with ingestion, ADR-0026).

        The ad half is OPTIONAL: with no IMPERION_META_AD_ACCOUNT_ID the ad collector returns
        nothing and the run proceeds with organic post/media metrics only. Incremental window
        from IMPERION_META_SINCE_DAYS (default 7; 0 = full) for the post enumeration.

        GATED: until IMPERION_META_PAGE_ID + the token are provisioned (and 0075 applied) the
        task logs the gap and exits cleanly; the next run converges (idempotent upsert + ON
        CONFLICT merge). Spend/amount values are not logged (counts/ids only). Requires
        Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionSocialMetricSync
    #>
    [CmdletBinding()]
    param()

    $pageId = $env:IMPERION_META_PAGE_ID
    if (-not $pageId) {
        Write-ImperionLog -Level Warn -Source 'meta' -Message 'social metric sync skipped: set IMPERION_META_PAGE_ID (discover with Get-ImperionMetaPageToken -Discover).'
        return
    }

    $sinceDays = if ($env:IMPERION_META_SINCE_DAYS) { [int]$env:IMPERION_META_SINCE_DAYS } else { 7 }
    $since = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

    try {
        $pageToken = Get-ImperionMetaPageToken -PageId $pageId

        # Organic post + media insights.
        $postParameters = @{ PageId = $pageId; Token = $pageToken }
        if ($since) { $postParameters.Since = $since }
        $posts = @(Get-ImperionMetaPagePost @postParameters)
        $posts | Get-ImperionMetaPostInsight -Token $pageToken | Set-ImperionMetaInsightToBronze

        $media = @(Get-ImperionInstagramMedia -PageId $pageId -Token $pageToken)
        $mediaIds = @($media | ForEach-Object { [string]$_.external_id } | Where-Object { $_ })
        if ($mediaIds.Count -gt 0) {
            Get-ImperionMetaPostInsight -MediaId $mediaIds -Token $pageToken | Set-ImperionMetaInsightToBronze
        }

        # Paid ad + campaign insights (optional — fail-soft when no ad account is configured).
        # The system-user token (not the page token) reads the Marketing API ad account.
        Get-ImperionMetaAdInsight -Level campaign | Set-ImperionMetaInsightToBronze
        Get-ImperionMetaAdInsight -Level ad | Set-ImperionMetaInsightToBronze

        Invoke-ImperionSocialMetricMerge
    }
    catch {
        # Credential/migration gate: an unreachable token or a not-yet-applied 0075 must not
        # crash the schedule — log loudly and exit; the next run converges.
        Write-ImperionLog -Level Warn -Source 'meta' -Message "social metric sync skipped (token provisioned? 0075 applied?): $($_.Exception.Message)"
    }
}
