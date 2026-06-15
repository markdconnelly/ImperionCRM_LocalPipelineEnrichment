# qbo/chart-of-accounts - daily QuickBooks Online expense-account pull -> bronze (qbo_expense_account).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (qbo-access-token / qbo-realm-id,
# CLAUDE.md §2; shared with qbo/bill-payments). DOUBLE-GATED: until (a) the operator provisions
# both secrets AND (b) the front-end qbo_expense_account bronze migration lands, the task logs
# the gap and exits cleanly (never crashes the schedule) - see docs/integrations/quickbooks-online.md.
# QuickBooks is the CATEGORY system of record; this pull is READ-ONLY (the app never writes QBO).
# A front-end admin maps each synced account to a website expense_category (front-end #489).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion qbo chart-of-accounts' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\chart-of-accounts.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental window; set IMPERION_QBO_SINCE_DAYS=0 for a full backfill (no modifiedAfter).
# The chart of accounts is small and slow-changing - a full backfill is cheap and the default
# incremental window keeps re-runs trivial.
$sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionQboExpenseAccount @collectorParameters | Set-ImperionQboExpenseAccountToBronze
}
catch {
    # Credential / schema gate: an unreachable qbo-access-token (QBO tokens EXPIRE ~1h and the
    # refresh token rotates) or a not-yet-created qbo_expense_account table must not crash the
    # schedule - log loudly and exit; the operator provisions/rotates and the next run converges
    # (idempotent upsert on the QBO Account Id). Account names are reference data, not PII.
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO chart-of-accounts sync skipped: $($_.Exception.Message)"
}
