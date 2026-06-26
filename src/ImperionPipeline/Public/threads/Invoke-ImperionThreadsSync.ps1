function Invoke-ImperionThreadsSync {
    <#
    .SYNOPSIS
        Collect Threads posts, replies, mentions, and insights into bronze, then run the Threads silver merge.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) for the
        `threads` source (LocalPipeline #356, front-end Threads epic #1334 / ADR-0125). The
        scheduled entry point: resolves the long-lived Threads token from the credential
        registry (`conn-company-threads`, ADR-0103), collects our own posts → replies on them →
        public mentions of us → profile + per-post insights over one shared DB connection, then
        runs Invoke-ImperionThreadsMerge (merge co-locates with ingestion, ADR-0026).

        DORMANT-SAFE: with no active company `threads` connection (token not entered / App Review
        not yet cleared) every collector's Resolve-ImperionThreadsToken -FailClosed throws and
        the catch below logs the gap and exits cleanly — the task is safe to schedule before the
        connector is seeded. An unapplied 0208 bronze migration fails the same way (fail loud,
        never create tables, §6). The next run converges (idempotent upsert + NOT-EXISTS merge).

        Incremental window from IMPERION_THREADS_SINCE_DAYS (default 7; 0 = full backfill).
        Profile insights use IMPERION_THREADS_USER_ID when set (else profile insights are
        skipped, per-post insights still run). Post/reply/mention TEXT is PII-adjacent — never
        logged. The token is held in memory only, never logged or persisted. Requires
        Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionThreadsSync
    #>
    [CmdletBinding()]
    param()

    $started = Get-Date
    $conn = New-ImperionDbConnection
    try {
        # Fail-closed token resolve up front: not connected -> log + no-op (dormant-safe).
        $token = Resolve-ImperionThreadsToken -Connection $conn
        if (-not $token) {
            Write-ImperionLog -Source 'threads' -Message 'No active company Threads connection (conn-company-threads); nothing to sync.'
            return
        }

        $sinceDays = if ($env:IMPERION_THREADS_SINCE_DAYS) { [int]$env:IMPERION_THREADS_SINCE_DAYS } else { 7 }
        $since = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }
        $threadsUserId = $env:IMPERION_THREADS_USER_ID

        $postParameters = @{ Token = $token }
        if ($since) { $postParameters.Since = $since }
        $posts = @(Get-ImperionThreadsPost @postParameters)
        if ($posts.Count -gt 0) { $posts | Set-ImperionThreadsPostToBronze -Connection $conn }

        # Replies under our posts (timeline, direction by author in the merge).
        $posts | Get-ImperionThreadsReply -Token $token | Set-ImperionThreadsReplyToBronze -Connection $conn

        # Public mentions OF us.
        $mentionParameters = @{ Token = $token }
        if ($since) { $mentionParameters.Since = $since }
        Get-ImperionThreadsMention @mentionParameters | Set-ImperionThreadsMentionToBronze -Connection $conn

        # Profile (when IMPERION_THREADS_USER_ID set) + per-post insights.
        $insightParameters = @{ Token = $token }
        if ($threadsUserId) { $insightParameters.ThreadsUserId = $threadsUserId }
        $posts | Get-ImperionThreadsInsight @insightParameters | Set-ImperionThreadsInsightToBronze -Connection $conn

        Invoke-ImperionThreadsMerge -Connection $conn

        Write-ImperionLog -Level Metric -Source 'threads' -Message 'Threads sync complete.' -Data @{
            posts      = $posts.Count
            duration_s = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
    catch {
        # Credential/migration gate: an unreachable token or a not-yet-applied 0208 must not
        # crash the schedule - log loudly and exit; the next run converges (idempotent).
        Write-ImperionLog -Level Warn -Source 'threads' -Message "threads sync skipped (conn-company-threads seeded? 0208 applied?): $($_.Exception.Message)"
    }
    finally {
        $conn.Dispose()
    }
}
