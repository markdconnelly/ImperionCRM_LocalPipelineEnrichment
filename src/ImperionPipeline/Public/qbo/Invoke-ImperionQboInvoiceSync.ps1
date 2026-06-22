function Invoke-ImperionQboInvoiceSync {
    <#
    .SYNOPSIS
        Collect QuickBooks Online invoices into the qbo_invoices bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/qbo/invoices.task.ps1. Read-only QBO finance pull (ADR-0020); fails closed
        (logs + exits) until qbo-access-token/qbo-realm-id are provisioned. Idempotent. Requires
        Initialize-ImperionContext. Invoice amounts/customer names are financial PII and are never
        logged (counts only).
    .EXAMPLE
        Invoke-ImperionQboInvoiceSync
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
        Get-ImperionQboInvoice @collectorParameters | Set-ImperionQboInvoiceToBronze
    }
    catch {
        # Credential gate: an unreachable/expired qbo-access-token must not crash the schedule - log
        # loudly and exit; the operator provisions/rotates and the next run converges (idempotent
        # upsert on the QBO invoice Id). Never log amounts or customer names.
        Write-ImperionLog -Level Warn -Source 'qbo' -Message "QBO invoice sync skipped: $($_.Exception.Message)"
    }
}
