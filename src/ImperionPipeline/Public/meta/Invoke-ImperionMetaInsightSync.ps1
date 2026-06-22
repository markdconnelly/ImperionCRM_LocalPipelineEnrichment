function Invoke-ImperionMetaInsightSync {
    <#
    .SYNOPSIS
        Collect FB Page + IG organic insight snapshots into bronze, then run the Meta silver merge.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/meta/insights.task.ps1. Page-token hop per #133, then Get-ImperionMetaInsight ->
        bronze and Invoke-ImperionMetaMerge (meta_insights -> social_metric). GATED like Meta social:
        until IMPERION_META_PAGE_ID + the token are provisioned (and 0075 applied) the task logs the gap
        and exits cleanly. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionMetaInsightSync
    #>
    [CmdletBinding()]
    param()

    $pageId = $env:IMPERION_META_PAGE_ID
    if (-not $pageId) {
        Write-ImperionLog -Level Warn -Source 'meta' -Message 'meta insights sync skipped: set IMPERION_META_PAGE_ID (discover with Get-ImperionMetaPageToken -Discover).'
        return
    }

    try {
        # Page-token hop per #133 (New Pages Experience) — see Invoke-ImperionMetaSocialSync.
        $pageToken = Get-ImperionMetaPageToken -PageId $pageId
        Get-ImperionMetaInsight -PageId $pageId -Token $pageToken | Set-ImperionMetaInsightToBronze
        Invoke-ImperionMetaMerge
    }
    catch {
        # Credential/migration gate: log loudly and exit cleanly; the next run converges.
        Write-ImperionLog -Level Warn -Source 'meta' -Message "meta insights sync skipped (token provisioned? 0075 applied?): $($_.Exception.Message)"
    }
}
