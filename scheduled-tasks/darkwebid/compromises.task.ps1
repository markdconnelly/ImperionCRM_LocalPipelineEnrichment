# darkwebid/compromises - daily Dark Web ID compromise pull -> bronze (darkwebid_exposures).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Dark Web ID is a COMPANY credential in Key Vault (conn-company-darkwebid,
# ADR-0040), read here via the cert SP — not a local SecretStore secret (CLAUDE.md §2).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion darkwebid compromises' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\darkwebid\compromises.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Optionally scope to one client domain via IMPERION_DARKWEBID_DOMAIN (omit for all).
$apiKey = Get-ImperionKeyVaultSecret -Name 'conn-company-darkwebid'

if ($env:IMPERION_DARKWEBID_DOMAIN) {
    Get-ImperionDarkWebIdCompromise -ApiKey $apiKey -Domain $env:IMPERION_DARKWEBID_DOMAIN | Set-ImperionDarkWebIdCompromiseToBronze
}
else {
    Get-ImperionDarkWebIdCompromise -ApiKey $apiKey | Set-ImperionDarkWebIdCompromiseToBronze
}
