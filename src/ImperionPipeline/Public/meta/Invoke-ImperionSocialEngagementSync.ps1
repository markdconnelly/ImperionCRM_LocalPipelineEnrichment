function Invoke-ImperionSocialEngagementSync {
    <#
    .SYNOPSIS
        Collect FB/IG post comments into bronze, then merge them to the silver social_engagement store.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) for slice
        H of the front-end Social plane (#357; epic #1338 / ADR-0124 decision 2). Promotes
        scheduled-tasks/meta/engagement.task.ps1. Hops to the Page token once (New Pages
        Experience, #133), collects post + media comments into the 0075 comment bronze tables,
        then runs Invoke-ImperionSocialEngagementMerge (comments → silver social_engagement; the
        merge co-locates with ingestion, ADR-0026). v1 lands COMMENTS only — brand mentions are
        deferred until a Meta mention bronze table exists (front-end issue, see docs/integrations/
        meta.md). Incremental window from IMPERION_META_SINCE_DAYS (default 7; 0 = full).

        GATED: until IMPERION_META_PAGE_ID + the token are provisioned (and 0075 applied) the
        task logs the gap and exits cleanly; the next run converges (idempotent upsert + ON
        CONFLICT merge). Comment bodies + author names are third-party content — never logged.
        Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionSocialEngagementSync
    #>
    [CmdletBinding()]
    param()

    $pageId = $env:IMPERION_META_PAGE_ID
    if (-not $pageId) {
        Write-ImperionLog -Level Warn -Source 'meta' -Message 'social engagement sync skipped: set IMPERION_META_PAGE_ID (discover with Get-ImperionMetaPageToken -Discover).'
        return
    }

    $sinceDays = if ($env:IMPERION_META_SINCE_DAYS) { [int]$env:IMPERION_META_SINCE_DAYS } else { 7 }
    $since = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

    try {
        # New Pages Experience rejects the system-user token for page-scoped reads (#133): hop
        # to the PAGE token once and pass it to every get. Held in memory only, never logged.
        $pageToken = Get-ImperionMetaPageToken -PageId $pageId

        $postParameters = @{ PageId = $pageId; Token = $pageToken }
        if ($since) { $postParameters.Since = $since }
        $posts = @(Get-ImperionMetaPagePost @postParameters)
        $posts | Get-ImperionMetaPostComment -Token $pageToken | Set-ImperionMetaCommentToBronze

        $media = @(Get-ImperionInstagramMedia -PageId $pageId -Token $pageToken)
        $media | Get-ImperionInstagramComment -Token $pageToken | Set-ImperionInstagramCommentToBronze

        Invoke-ImperionSocialEngagementMerge
    }
    catch {
        # Credential/migration gate: an unreachable token or a not-yet-applied 0075/0210 must
        # not crash the schedule — log loudly and exit; the next run converges.
        Write-ImperionLog -Level Warn -Source 'meta' -Message "social engagement sync skipped (token provisioned? 0075/0210 applied? grant present?): $($_.Exception.Message)"
    }
}
