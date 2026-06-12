# kqm/proposals - daily Kaseya Quote Manager quote pull -> bronze (kqm_proposals).
# Cadence: Daily (scheduled-tasks/README.md); the API allows 60/min + 20k/day - one daily
# incremental page-walk is far inside budget. Credential: SecretStore 'kqm-api-key' mirror,
# else Key Vault 'KQM-API-Key' via the cert SP (issue #98). GATED: until the key is
# reachable, the task logs the gap and exits cleanly (never crashes the schedule).
# KQM URLs are secret-bearing (?apikey=) - never add logging of request URLs here.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion kqm proposals' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\kqm\proposals.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental window; set IMPERION_KQM_SINCE_DAYS=0 for a full backfill (no modifiedAfter).
$sinceDays = if ($env:IMPERION_KQM_SINCE_DAYS) { [int]$env:IMPERION_KQM_SINCE_DAYS } else { 7 }
$modifiedAfter = if ($sinceDays -le 0) { $null } else { (Get-Date).AddDays(-$sinceDays).ToUniversalTime().ToString('o') }

try {
    $collectorParameters = @{}
    if ($modifiedAfter) { $collectorParameters.ModifiedAfter = $modifiedAfter }
    Get-ImperionKqmProposal @collectorParameters | Set-ImperionKqmProposalToBronze
}
catch {
    # Credential gate: an unreachable kqm-api-key / KQM-API-Key must not crash the
    # schedule - log loudly and exit; the operator provisions/rotates and the next run
    # converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'kqm' -Message "KQM proposal sync skipped: $($_.Exception.Message)"
}
