# easydmarc/domains - daily EasyDMARC domain/DMARC posture pull -> bronze (easydmarc_domains).
# Cadence: Daily (scheduled-tasks/README.md); domain posture is slow-changing and the API is
# rate-limited per key, so one daily page-walk is well inside budget. Credential: SecretStore
# 'easydmarc-api-key' mirror, else Key Vault 'EasyDMARC-API-Key' via the cert SP (a COMPANY
# credential - Imperion's MSP account). Auth is an Authorization: Bearer header, so URLs are
# NOT secret-bearing.
#
# GATED (issue #122): until BOTH the API key is reachable AND the front-end bronze migration
# for easydmarc_domains is applied (proposed in ImperionCRM issue #581), the task logs
# the gap and exits cleanly - it never crashes the schedule. Registration is deferred to the
# server bringup (#102), same as the other gated sources.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion easydmarc domains' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\easydmarc\domains.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Get-ImperionEasyDmarcDomain | Set-ImperionEasyDmarcDomainToBronze
}
catch {
    # Credential / schema gate: an unreachable easydmarc-api-key / EasyDMARC-API-Key, or a
    # missing easydmarc_domains table, must not crash the schedule - log loudly and exit; the
    # operator provisions/rotates the key (and the front-end applies the migration) and the
    # next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'easydmarc' -Message "EasyDMARC domain sync skipped: $($_.Exception.Message)"
}
