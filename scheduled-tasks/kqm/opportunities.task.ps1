# kqm/opportunities - daily Kaseya Quote Manager pull -> bronze. Chains header -> won-detail
# (issue #161): the quote HEADER -> kqm_opportunities, then for WON quotes only (status 3) the
# DETAIL (sections/lines/sales orders/order lines) -> the four kqm_* detail tables.
# Cadence: Daily (scheduled-tasks/README.md); the API allows 60/min + 20k/day - one daily
# incremental header walk plus a won-only detail pull is far inside budget. Credential:
# SecretStore 'kqm-api-key' mirror, else Key Vault 'KQM-API-Key' via the cert SP. GATED: until
# the key is reachable, the task logs the gap and exits cleanly (never crashes the schedule).
# Target = kqm_opportunities + kqm_opportunity_sections/_lines + kqm_sales_orders/_order_lines
# (front-end migration 0083, ADR-0080/0039). Detail value (Σ selected lines, MRR split) is
# computed in the silver opportunity merge (pipeline #95), not here.
# Detail endpoints are NOT server-filterable by quote and modifiedAfter is unverified there
# (#427) -> the detail getter does a full pull and relies on the bronze content-hash skip.
# KQM URLs are secret-bearing (?apikey=) - never add logging of request URLs here.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion kqm opportunities' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\kqm\opportunities.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

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
