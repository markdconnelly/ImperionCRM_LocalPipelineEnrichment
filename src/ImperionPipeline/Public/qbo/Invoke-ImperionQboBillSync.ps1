function Invoke-ImperionQboBillSync {
    <#
    .SYNOPSIS
        Collect QuickBooks Online vendor bills (A/P) into the qbo_bills bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/bills.task.ps1. Read-only QBO finance pull (ADR-0020); fails closed
        (logs + exits) until qbo-access-token/qbo-realm-id are provisioned. Idempotent. Requires
        Initialize-ImperionContext. The company is Simple Start (no Accounts Payable), so QBO may
        return "Feature Not Supported" for Bill; Get-ImperionQboBill handles that inside the
        collector (warns + yields no rows) and qbo_bills stays dormant — only credential/transport
        failures reach the catch.
    .EXAMPLE
        Invoke-ImperionQboBillSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

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
}
