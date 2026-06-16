# myitprocess/recommendations - daily myITprocess recommendation pull -> bronze
# (myitprocess_recommendations). Cadence: Daily (scheduled-tasks/README.md); strategic roadmap /
# QBR / assessment recommendations change slowly. Credential: SecretStore 'myitprocess-api-key'
# mirror, else Key Vault 'myITprocess-API-Key' via the cert SP (an MSP-WIDE vendor credential,
# ADR-0018). Auth is the api_token header, so URLs are NOT secret-bearing.
#
# GATED (issue #195, ADR-0018): the front-end bronze migration 0119 (myitprocess_recommendations)
# is SHIPPED + prod-applied (front-end #674), so the SCHEMA gate is clear. The remaining gate is
# the API key: until 'myitprocess-api-key' / 'myITprocess-API-Key' is provisioned (Mark-gated),
# the task logs the gap and exits cleanly. Registration is deferred to the server bringup (#102).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion myitprocess recommendations' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\myitprocess\recommendations.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Get-ImperionMyItProcessRecommendation | Set-ImperionMyItProcessRecommendationToBronze
}
catch {
    # Credential / schema gate: an unreachable myitprocess-api-key / myITprocess-API-Key, or a
    # missing myitprocess_recommendations table, must not crash the schedule - log loudly and exit;
    # the next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'myitprocess' -Message "myITprocess recommendation sync skipped: $($_.Exception.Message)"
}
