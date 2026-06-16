# qbo/purchases - daily QuickBooks Online purchase (Check/Expense) pull -> bronze (qbo_purchases).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (qbo-access-token / qbo-realm-id,
# CLAUDE.md §2). GATED: until the operator provisions both secrets the task logs the gap and
# exits cleanly (never crashes the schedule) - see docs/integrations/quickbooks-online.md. QBO is
# read-only and authoritative ONLY for the payment fact (the app never pays); the backend Payroll
# Reconciliation reads this bronze to set a timesheet Paid (front-end ADR-0082/ADR-0085).
#
# WHY Purchase (not BillPayment): the QBO company is Simple Start - no Accounts Payable, so
# Bill/BillPayment return "Feature Not Supported". 1099 payments / reimbursements are recorded as
# Checks/Expenses = the Purchase entity (ADR-0014; front-end migration 0092, #526).
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion qbo purchases' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\purchases.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental window; set IMPERION_QBO_SINCE_DAYS=0 for a full backfill (no modifiedAfter).
$sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionQboPurchase @collectorParameters | Set-ImperionQboPurchaseToBronze
}
catch {
    # Credential gate: an unreachable qbo-access-token (QBO tokens EXPIRE ~1h and the refresh
    # token rotates) must not crash the schedule - log loudly and exit; the operator
    # provisions/rotates and the next run converges (idempotent upsert on the QBO purchase Id).
    # Never log the payment amount/payee.
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO purchase sync skipped: $($_.Exception.Message)"
}
