# dattobcdr/backups - daily Datto BCDR backup-posture pull -> bronze (datto_bcdr_backups).
# Cadence: Daily (scheduled-tasks/README.md); per-device backup posture (protected / last-good
# backup) is checked daily. Credential: SecretStore 'datto-bcdr-api-key' mirror, else Key Vault
# 'Datto-BCDR-API-Key' via the cert SP (an MSP-WIDE vendor credential, ADR-0018). Auth is an
# Authorization: Bearer header, so URLs are NOT secret-bearing.
#
# GATED (issue #195, ADR-0018): the front-end bronze migration 0119 (datto_bcdr_backups) is SHIPPED
# + prod-applied (front-end #674), so the SCHEMA gate is clear. The remaining gate is the API key:
# until 'datto-bcdr-api-key' / 'Datto-BCDR-API-Key' is provisioned (Mark-gated), the task logs the
# gap and exits cleanly. Registration is deferred to the server bringup (#102).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion dattobcdr backups' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\dattobcdr\backups.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Get-ImperionDattoBcdrBackup | Set-ImperionDattoBcdrBackupToBronze
}
catch {
    # Credential / schema gate: an unreachable datto-bcdr-api-key / Datto-BCDR-API-Key, or a missing
    # datto_bcdr_backups table, must not crash the schedule - log loudly and exit; the next run
    # converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'datto_bcdr' -Message "Datto BCDR backup sync skipped: $($_.Exception.Message)"
}
