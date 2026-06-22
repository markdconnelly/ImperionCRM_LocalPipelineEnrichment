function Invoke-ImperionQboPurchaseSync {
    <#
    .SYNOPSIS
        Collect QuickBooks Online purchases (Check/Expense) into the qbo_purchases bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/purchases.task.ps1. Read-only QBO finance pull (ADR-0020); QBO is
        authoritative only for the payment fact (the app never pays). Fails closed (logs + exits)
        until qbo-access-token/qbo-realm-id are provisioned. Idempotent. Requires
        Initialize-ImperionContext. The company is Simple Start (no A/P), so 1099 payments /
        reimbursements are recorded as Checks/Expenses = the Purchase entity (ADR-0014); the backend
        Payroll Reconciliation reads this bronze (front-end ADR-0082/ADR-0085). Payee/amount never
        logged.
    .EXAMPLE
        Invoke-ImperionQboPurchaseSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

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
}
