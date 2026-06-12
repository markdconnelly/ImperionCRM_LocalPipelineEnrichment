# meta/insights - daily Page + IG organic insight snapshots -> bronze (meta_insights,
# front-end migration 0075), then the local silver merge (Invoke-ImperionMetaMerge:
# meta_insights -> social_metric; the other merge steps are idempotent no-ops here).
# Cadence: Daily (scheduled-tasks/README.md) - period=day metrics produce one point per
# day; metrics are requested ONE AT A TIME so a deprecated metric warns and never aborts
# the run. Credential (the KQM pattern, ADR-0013): SecretStore mirror
# 'meta-system-user-token', else Key Vault original 'Meta-SystemUser-Token'.
# GATED like meta/social. Registration deferred to server bringup (#102).
#
#   Register-ImperionTask -Name 'Imperion meta insights' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\meta\insights.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

$pageId = $env:IMPERION_META_PAGE_ID
if (-not $pageId) {
    Write-ImperionLog -Level Warn -Source 'meta' -Message 'meta insights sync skipped: set IMPERION_META_PAGE_ID (discover with Get-ImperionMetaPageToken -Discover).'
    return
}

try {
    Get-ImperionMetaInsight -PageId $pageId | Set-ImperionMetaInsightToBronze
    Invoke-ImperionMetaMerge
}
catch {
    # Credential/migration gate: log loudly and exit cleanly; the next run converges.
    Write-ImperionLog -Level Warn -Source 'meta' -Message "meta insights sync skipped (token provisioned? 0075 applied?): $($_.Exception.Message)"
}
