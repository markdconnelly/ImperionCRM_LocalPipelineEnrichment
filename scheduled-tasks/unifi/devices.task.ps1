# unifi/devices - daily UniFi device inventory + config-compliance pull -> bronze (unifi_devices).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). UniFi is a per-customer COMPANY credential in Key Vault (conn-company-unifi,
# issue #73 locked design: JSON blob { apiKey, connectionType: console|cloud, host }), read
# here via the cert SP - not a local SecretStore secret (CLAUDE.md §2).
#
# DOUBLE-GATED until operator steps land (logs + exits cleanly, never crashes the schedule):
#   1. the conn-company-unifi credential must exist in Key Vault;
#   2. the unifi_devices bronze table needs the front-end migration (schema handoff,
#      docs/integrations/unifi.md) - the upsert fails loudly until it lands.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion unifi devices' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\unifi\devices.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $credentialJson = Get-ImperionKeyVaultSecret -Name 'conn-company-unifi'
    $credential = $credentialJson | ConvertFrom-Json

    $deviceParameters = @{
        ApiKey         = $credential.apiKey
        ConnectionType = $credential.connectionType
    }
    if ($credential.connectionType -eq 'console') { $deviceParameters.ControllerHost = $credential.host }

    Get-ImperionUniFiDevice @deviceParameters | Set-ImperionUniFiDeviceToBronze
}
catch {
    # Credential or schema gate: log loudly and exit; the operator provisions the missing
    # piece and the next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'unifi' -Message "UniFi device sync skipped: $($_.Exception.Message)"
}
