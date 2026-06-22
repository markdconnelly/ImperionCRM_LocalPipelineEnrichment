function Invoke-ImperionMetaSocialSync {
    <#
    .SYNOPSIS
        Collect FB Page posts/comments/DMs + IG media/comments into bronze, then run the Meta silver merge.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/meta/social.task.ps1. Hops to the Page token once (New Pages Experience, #133)
        and passes it to every get, then runs Invoke-ImperionMetaMerge. Incremental window from
        IMPERION_META_SINCE_DAYS (default 7; 0 = full). GATED: until IMPERION_META_PAGE_ID + the token
        are provisioned (and 0075 applied) the task logs the gap and exits cleanly. DM payloads are PII -
        never logged. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionMetaSocialSync
    #>
    [CmdletBinding()]
    param()

    $pageId = $env:IMPERION_META_PAGE_ID
    if (-not $pageId) {
        Write-ImperionLog -Level Warn -Source 'meta' -Message 'meta social sync skipped: set IMPERION_META_PAGE_ID (discover with Get-ImperionMetaPageToken -Discover).'
        return
    }

    # Incremental window for posts; set IMPERION_META_SINCE_DAYS=0 for a full backfill.
    $sinceDays = if ($env:IMPERION_META_SINCE_DAYS) { [int]$env:IMPERION_META_SINCE_DAYS } else { 7 }
    $since = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

    try {
        # New Pages Experience rejects the system-user token for page-scoped reads
        # (OAuthException 2069032, verified live 2026-06-12, #133): hop to the PAGE
        # token once and pass it to every get. Held in memory only, never logged.
        $pageToken = Get-ImperionMetaPageToken -PageId $pageId

        $postParameters = @{ PageId = $pageId; Token = $pageToken }
        if ($since) { $postParameters.Since = $since }
        $posts = @(Get-ImperionMetaPagePost @postParameters)
        $posts | Set-ImperionMetaPostToBronze
        $posts | Get-ImperionMetaPostComment -Token $pageToken | Set-ImperionMetaCommentToBronze

        Get-ImperionMetaConversation -PageId $pageId -PageToken $pageToken | Set-ImperionMetaMessageToBronze

        $media = @(Get-ImperionInstagramMedia -PageId $pageId -Token $pageToken)
        $media | Set-ImperionInstagramMediaToBronze
        $media | Get-ImperionInstagramComment -Token $pageToken | Set-ImperionInstagramCommentToBronze

        Invoke-ImperionMetaMerge
    }
    catch {
        # Credential/migration gate: an unreachable meta-system-user-token or a not-yet-
        # applied 0075 must not crash the schedule - log loudly and exit; the next run
        # converges (idempotent upsert + NOT-EXISTS merge).
        Write-ImperionLog -Level Warn -Source 'meta' -Message "meta social sync skipped (token provisioned? 0075 applied?): $($_.Exception.Message)"
    }
}
