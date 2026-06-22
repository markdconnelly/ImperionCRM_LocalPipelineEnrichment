function Invoke-ImperionQboCustomerSync {
    <#
    .SYNOPSIS
        Collect QuickBooks Online customers into the qbo_customers bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/customers.task.ps1. Read-only QBO finance pull (ADR-0020); fails closed
        (logs + exits) until qbo-access-token/qbo-realm-id are provisioned. Idempotent. Requires
        Initialize-ImperionContext. The finance-side customer master that joins to the silver
        account; names/emails/phones/balances are PII and are never logged.
    .EXAMPLE
        Invoke-ImperionQboCustomerSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

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
}
