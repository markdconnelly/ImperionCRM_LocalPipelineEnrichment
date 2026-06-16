# qbo/profit-and-loss - monthly QuickBooks Online P&L report snapshot -> bronze
# (qbo_profit_and_loss). Cadence: Daily/Monthly (the snapshot is idempotent on the period, so a
# daily re-pull of the current month converges and only changes when the report changes). Composes
# one get + one post; keep this short (CLAUDE.md §1). Credentials are SecretStore secrets
# (qbo-access-token / qbo-realm-id, CLAUDE.md §2). GATED: until the operator provisions both
# secrets the task logs the gap and exits cleanly. Part of the read-only full QBO finance pull
# (ADR-0020, issue #197). Report, not entity - pulls the QBO Reports API. Totals never logged.
#
# Defaults to the current calendar month (first-of-month .. today, UTC). Override the window with
# IMPERION_QBO_PNL_START / IMPERION_QBO_PNL_END (ISO 'yyyy-MM-dd') for a backfill of a prior period.
#
#   Register-ImperionTask -Name 'Imperion qbo profit-and-loss' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\profit-and-loss.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $reportParameters = @{}
    if ($env:IMPERION_QBO_PNL_START) { $reportParameters.StartDate = $env:IMPERION_QBO_PNL_START }
    if ($env:IMPERION_QBO_PNL_END) { $reportParameters.EndDate = $env:IMPERION_QBO_PNL_END }
    Get-ImperionQboProfitAndLoss @reportParameters | Set-ImperionQboProfitAndLossToBronze
}
catch {
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO profit-and-loss snapshot skipped: $($_.Exception.Message)"
}
