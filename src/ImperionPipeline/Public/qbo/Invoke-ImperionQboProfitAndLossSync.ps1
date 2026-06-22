function Invoke-ImperionQboProfitAndLossSync {
    <#
    .SYNOPSIS
        Snapshot the QuickBooks Online profit-and-loss report into the qbo_profit_and_loss bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/profit-and-loss.task.ps1. Read-only QBO finance pull (ADR-0020); fails
        closed (logs + exits) until qbo-access-token/qbo-realm-id are provisioned. Idempotent on the
        period (a daily re-pull of the current month converges). Requires Initialize-ImperionContext.
        Defaults to the current calendar month (first-of-month .. today, UTC); override the window
        with -StartDate/-EndDate or IMPERION_QBO_PNL_START/IMPERION_QBO_PNL_END (ISO 'yyyy-MM-dd').
        Totals are never logged.
    .PARAMETER StartDate
        Report window start (ISO 'yyyy-MM-dd'). Falls back to $env:IMPERION_QBO_PNL_START, then the
        collector's default (first-of-month).
    .PARAMETER EndDate
        Report window end (ISO 'yyyy-MM-dd'). Falls back to $env:IMPERION_QBO_PNL_END, then the
        collector's default (today).
    .EXAMPLE
        Invoke-ImperionQboProfitAndLossSync
    .EXAMPLE
        Invoke-ImperionQboProfitAndLossSync -StartDate '2026-01-01' -EndDate '2026-01-31'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string] $StartDate, [string] $EndDate)
    if (-not $PSBoundParameters.ContainsKey('StartDate') -and $env:IMPERION_QBO_PNL_START) { $StartDate = $env:IMPERION_QBO_PNL_START }
    if (-not $PSBoundParameters.ContainsKey('EndDate')   -and $env:IMPERION_QBO_PNL_END)   { $EndDate   = $env:IMPERION_QBO_PNL_END }

    try {
        $reportParameters = @{}
        if ($StartDate) { $reportParameters.StartDate = $StartDate }
        if ($EndDate) { $reportParameters.EndDate = $EndDate }
        Get-ImperionQboProfitAndLoss @reportParameters | Set-ImperionQboProfitAndLossToBronze
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO profit-and-loss snapshot skipped: $($_.Exception.Message)"
    }
}
