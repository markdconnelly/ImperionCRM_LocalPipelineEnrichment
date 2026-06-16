# qbo/customers - daily QuickBooks Online customer pull -> bronze (qbo_customers).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (qbo-access-token / qbo-realm-id, CLAUDE.md
# §2). GATED: until the operator provisions both secrets the task logs the gap and exits cleanly.
# Part of the read-only full QBO finance pull (ADR-0020, issue #197); the finance-side customer
# master that joins to the silver account. Names/emails/phones/balances are PII - never logged.
#
#   Register-ImperionTask -Name 'Imperion qbo customers' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\customers.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

$sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionQboCustomer @collectorParameters | Set-ImperionQboCustomerToBronze
}
catch {
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO customer sync skipped: $($_.Exception.Message)"
}
