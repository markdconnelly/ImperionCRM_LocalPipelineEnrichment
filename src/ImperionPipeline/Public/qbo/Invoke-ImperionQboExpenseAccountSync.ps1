function Invoke-ImperionQboExpenseAccountSync {
    <#
    .SYNOPSIS
        Collect QuickBooks Online expense accounts into the qbo_expense_account bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/chart-of-accounts.task.ps1. Read-only QBO finance pull (ADR-0020); QBO is
        the CATEGORY system of record (the app never writes QBO). DOUBLE-GATED: fails closed (logs +
        exits) until both qbo-access-token/qbo-realm-id are provisioned AND the front-end
        qbo_expense_account bronze migration lands. Idempotent. Requires Initialize-ImperionContext.
        Expense-only — distinct from the FULL chart of accounts in Invoke-ImperionQboAccountSync.
    .EXAMPLE
        Invoke-ImperionQboExpenseAccountSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

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
}
