# qbo/invoices - daily QuickBooks Online invoice pull -> bronze (qbo_invoices).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (qbo-access-token / qbo-realm-id,
# CLAUDE.md §2). GATED: until the operator provisions both secrets the task logs the gap and
# exits cleanly (never crashes the schedule) - see docs/integrations/quickbooks-online.md. Part of
# the read-only full QBO finance pull into the intelligence engine (ADR-0020, issue #197). QBO is
# read-only; invoice amounts/customer names are financial PII and are never logged (counts only).
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion qbo invoices' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\invoices.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental window; set IMPERION_QBO_SINCE_DAYS=0 for a full backfill (no modifiedAfter).
$sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionQboInvoice @collectorParameters | Set-ImperionQboInvoiceToBronze
}
catch {
    # Credential gate: an unreachable/expired qbo-access-token must not crash the schedule - log
    # loudly and exit; the operator provisions/rotates and the next run converges (idempotent
    # upsert on the QBO invoice Id). Never log amounts or customer names.
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO invoice sync skipped: $($_.Exception.Message)"
}
