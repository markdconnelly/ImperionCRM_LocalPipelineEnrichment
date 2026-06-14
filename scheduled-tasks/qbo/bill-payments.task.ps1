# qbo/bill-payments - daily QuickBooks Online vendor bill-payment pull -> bronze (qbo_bill_payments).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (qbo-access-token / qbo-realm-id,
# CLAUDE.md §2). DOUBLE-GATED: until (a) the operator provisions both secrets AND (b) the
# front-end qbo_bill_payments bronze migration lands, the task logs the gap and exits cleanly
# (never crashes the schedule) - see docs/integrations/quickbooks-online.md. QBO is read-only
# and authoritative ONLY for the payment fact (the app never pays); the backend Payroll
# Reconciliation reads this bronze to set a timesheet Paid (front-end ADR-0082).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion qbo bill-payments' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\bill-payments.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental window; set IMPERION_QBO_SINCE_DAYS=0 for a full backfill (no modifiedAfter).
$sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionQboBillPayment @collectorParameters | Set-ImperionQboBillPaymentToBronze
}
catch {
    # Credential / schema gate: an unreachable qbo-access-token (QBO tokens EXPIRE ~1h and the
    # refresh token rotates) or a not-yet-created qbo_bill_payments table must not crash the
    # schedule - log loudly and exit; the operator provisions/rotates and the next run
    # converges (idempotent upsert on the QBO payment Id). Never log the payment amount/vendor.
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO bill-payment sync skipped: $($_.Exception.Message)"
}
