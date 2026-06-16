# qbo/accounts - daily QuickBooks Online FULL chart-of-accounts pull -> bronze (qbo_accounts).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (qbo-access-token / qbo-realm-id, CLAUDE.md
# §2). GATED: until the operator provisions both secrets the task logs the gap and exits cleanly.
# Part of the read-only full QBO finance pull (ADR-0020, issue #197). FULL chart of accounts (no
# Classification filter) - distinct from qbo/chart-of-accounts (expense-only, qbo_expense_account).
# Reference data (account names), not PII; the COA is small so a full backfill is cheap.
#
#   Register-ImperionTask -Name 'Imperion qbo accounts' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\accounts.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Default to a full backfill (the chart of accounts is small); set IMPERION_QBO_SINCE_DAYS>0 to
# pull only recently-changed accounts.
$sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 0 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionQboAccount @collectorParameters | Set-ImperionQboAccountToBronze
}
catch {
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO chart-of-accounts (full) sync skipped: $($_.Exception.Message)"
}
