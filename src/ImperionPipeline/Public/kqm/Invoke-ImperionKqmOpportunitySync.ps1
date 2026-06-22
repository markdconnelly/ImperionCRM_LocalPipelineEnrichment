function Invoke-ImperionKqmOpportunitySync {
    <#
    .SYNOPSIS
        Collect Kaseya Quote Manager opportunities (header -> won-detail) into the kqm_* bronze tables.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/kqm/opportunities.task.ps1. Chains the quote header -> kqm_opportunities, then
        for WON quotes only (status 3) the detail (sections/lines/sales orders/order lines) -> the four
        kqm_* detail tables (issue #161). Incremental window from IMPERION_KQM_SINCE_DAYS (default 7;
        0 = full backfill). KQM URLs are secret-bearing (?apikey=) - never logged. GATED: until the key
        is reachable the task logs the gap and exits cleanly. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionKqmOpportunitySync
    #>
    [CmdletBinding()]
    param()

    # Incremental window; set IMPERION_KQM_SINCE_DAYS=0 for a full backfill (no modifiedAfter).
    $sinceDays = if ($env:IMPERION_KQM_SINCE_DAYS) { [int]$env:IMPERION_KQM_SINCE_DAYS } else { 7 }
    $modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

    try {
        $collectorParameters = @{}
        if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }

        # Header pass: capture rows so the won set can drive the detail pull, then write.
        $headerRows = @(Get-ImperionKqmOpportunity @collectorParameters)
        $headerRows | Set-ImperionKqmOpportunityToBronze

        # Won quotes (status int enum 3) seen this pass scope the detail pull (issue #161).
        $wonQuoteIds = @($headerRows | Where-Object { "$($_.status)" -eq '3' } | ForEach-Object { $_.external_id })
        if ($wonQuoteIds.Count -gt 0) {
            Get-ImperionKqmOpportunityDetail -WonQuoteId $wonQuoteIds | Set-ImperionKqmOpportunityDetailToBronze
        }
        else {
            Write-ImperionLog -Level Info -Source 'kqm' -Message 'No won quotes in this pass - skipping detail pull.'
        }
    }
    catch {
        # Credential gate: an unreachable kqm-api-key / KQM-API-Key must not crash the
        # schedule - log loudly and exit; the operator provisions/rotates and the next run
        # converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'kqm' -Message "KQM opportunity sync skipped: $($_.Exception.Message)"
    }
}
