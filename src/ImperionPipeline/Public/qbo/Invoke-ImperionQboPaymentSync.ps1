function Invoke-ImperionQboPaymentSync {
    <#
    .SYNOPSIS
        Collect QuickBooks Online customer payments into the qbo_payments bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/payments.task.ps1. Read-only QBO finance pull (ADR-0020); fails closed
        (logs + exits) until qbo-access-token/qbo-realm-id are provisioned. Idempotent. Requires
        Initialize-ImperionContext. This is the CUSTOMER payment (cash IN) — distinct from
        Invoke-ImperionQboPurchaseSync (cash OUT); amounts/customer names are never logged.
    .EXAMPLE
        Invoke-ImperionQboPaymentSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
    $modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

    try {
        $collectorParameters = @{}
        if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
        Get-ImperionQboPayment @collectorParameters | Set-ImperionQboPaymentToBronze
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO payment sync skipped: $($_.Exception.Message)"
    }
}
