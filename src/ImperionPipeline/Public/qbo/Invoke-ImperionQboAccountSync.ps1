function Invoke-ImperionQboAccountSync {
    <#
    .SYNOPSIS
        Collect the QuickBooks Online FULL chart of accounts into the qbo_accounts bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/accounts.task.ps1. Read-only QBO finance pull (ADR-0020); fails closed
        (logs + exits) until qbo-access-token/qbo-realm-id are provisioned. Idempotent. Requires
        Initialize-ImperionContext. The FULL chart of accounts (no Classification filter) — distinct
        from the expense-only Invoke-ImperionQboExpenseAccountSync.
    .EXAMPLE
        Invoke-ImperionQboAccountSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

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
}
