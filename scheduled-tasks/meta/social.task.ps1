# meta/social - daily FB Page posts/comments/DMs + IG media/comments pull -> bronze
# (facebook_posts, facebook_comments, facebook_messages, instagram_media,
# instagram_comments, front-end migration 0075), then the local silver merge
# (Invoke-ImperionMetaMerge: interaction + DM-sender lead capture). Cadence: Daily
# (scheduled-tasks/README.md) - organic social is slow-moving; well inside Meta's
# per-app rate budget. Credential (the KQM pattern, ADR-0013): SecretStore mirror
# 'meta-system-user-token', else Key Vault original 'Meta-SystemUser-Token'.
# GATED: until IMPERION_META_PAGE_ID and
# the token are provisioned (and 0075 is applied to prod), the task logs the gap and
# exits cleanly (never crashes the schedule). DM payloads are PII - never add logging
# of row contents here. Registration deferred to server bringup (#102).
#
#   Register-ImperionTask -Name 'Imperion meta social' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\meta\social.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

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
