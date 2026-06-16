# dattormm/devices - daily Datto RMM managed-device pull -> bronze (datto_rmm_devices).
# Cadence: Daily (scheduled-tasks/README.md); device inventory + patch/AV state is slow-changing
# relative to a daily page-walk. Credential: SecretStore 'datto-rmm-api-key' mirror, else Key Vault
# 'Datto-RMM-API-Key' via the cert SP (an MSP-WIDE vendor credential, ADR-0018). Auth is an
# API-key -> short-lived BEARER exchange (the connect helper owns it; the token is never logged).
#
# GATED (issue #195, ADR-0018): the front-end bronze migration 0119 (datto_rmm_devices) is SHIPPED
# + prod-applied (front-end #674), so the SCHEMA gate is clear. The remaining gate is the API key:
# until 'datto-rmm-api-key' / 'Datto-RMM-API-Key' is provisioned (Mark-gated), the task logs the
# gap and exits cleanly - it never crashes the schedule. Registration is deferred to the server
# bringup (#102), same as the other gated sources.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion dattormm devices' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\dattormm\devices.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Get-ImperionDattoRmmDevice | Set-ImperionDattoRmmDeviceToBronze
}
catch {
    # Credential / schema gate: an unreachable datto-rmm-api-key / Datto-RMM-API-Key, or a missing
    # datto_rmm_devices table, must not crash the schedule - log loudly and exit; the operator
    # provisions/rotates the key and the next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'datto_rmm' -Message "Datto RMM device sync skipped: $($_.Exception.Message)"
}
