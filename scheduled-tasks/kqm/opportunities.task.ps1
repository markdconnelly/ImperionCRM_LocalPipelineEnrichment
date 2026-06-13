# kqm/opportunities - daily Kaseya Quote Manager quote-header pull -> bronze (kqm_opportunities).
# Cadence: Daily (scheduled-tasks/README.md); the API allows 60/min + 20k/day - one daily
# incremental page-walk is far inside budget. Credential: SecretStore 'kqm-api-key' mirror,
# else Key Vault 'KQM-API-Key' via the cert SP. GATED: until the key is reachable, the task
# logs the gap and exits cleanly (never crashes the schedule).
# Target = kqm_opportunities (front-end migration 0083, ADR-0080/0039); the won-quote detail
# (sections/lines/sales orders) is a separate task once issue #161 lands.
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
    Get-ImperionKqmOpportunity @collectorParameters | Set-ImperionKqmOpportunityToBronze
}
catch {
    # Credential gate: an unreachable kqm-api-key / KQM-API-Key must not crash the
    # schedule - log loudly and exit; the operator provisions/rotates and the next run
    # converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'kqm' -Message "KQM opportunity sync skipped: $($_.Exception.Message)"
}
