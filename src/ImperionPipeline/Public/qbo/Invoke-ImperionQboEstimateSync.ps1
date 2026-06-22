function Invoke-ImperionQboEstimateSync {
    <#
    .SYNOPSIS
        Collect QuickBooks Online estimates into the qbo_estimates bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/estimates.task.ps1. Read-only QBO finance pull (ADR-0020); fails closed
        (logs + exits) until qbo-access-token/qbo-realm-id are provisioned. Idempotent. Requires
        Initialize-ImperionContext. Estimates = committed-but-unbilled pipeline; amounts/customer
        names are never logged.
    .EXAMPLE
        Invoke-ImperionQboEstimateSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $sinceDays = if ($env:IMPERION_QBO_SINCE_DAYS) { [int]$env:IMPERION_QBO_SINCE_DAYS } else { 7 }
    $modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

    try {
        $collectorParameters = @{}
        if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
        Get-ImperionQboEstimate @collectorParameters | Set-ImperionQboEstimateToBronze
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO estimate sync skipped: $($_.Exception.Message)"
    }
}
