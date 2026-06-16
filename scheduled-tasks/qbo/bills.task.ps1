# qbo/bills - daily QuickBooks Online vendor-bill (A/P) pull -> bronze (qbo_bills).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (qbo-access-token / qbo-realm-id, CLAUDE.md
# §2). GATED: until the operator provisions both secrets the task logs the gap and exits cleanly.
# Part of the read-only full QBO finance pull (ADR-0020, issue #197); vendor bills = the A/P /
# procurement signal. Amounts/vendor names never logged.
#
# SIMPLE START / GRACEFUL DEGRADE (CONFIRM-BEFORE-LIVE): the company is Simple Start, which has no
# Accounts Payable - QBO may return "Feature Not Supported" for `Bill`. Get-ImperionQboBill handles
# that INSIDE the collector (warns + yields no rows), so qbo_bills simply stays dormant; the A/P
# signal is then carried by qbo_purchases + qbo_accounts. Only credential/transport failures reach
# the catch below.
#
#   Register-ImperionTask -Name 'Imperion qbo bills' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\qbo\bills.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

$sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionQboBill @collectorParameters | Set-ImperionQboBillToBronze
}
catch {
    Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO bill sync skipped: $($_.Exception.Message)"
}
