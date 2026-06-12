# m365/teams-chat - hourly cross-org Teams chat pull -> bronze (m365_teams_chats, migration 0065).
# Cadence: Hourly (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Single-tenant against the Imperion company tenant (Mark's 2026-06-11
# authorization; GDAP fan-out deferred).
#
# Configuration (GATED - logs + exits cleanly until set):
#   IMPERION_M365_USERS          comma-separated user UPNs whose chats to collect
#   IMPERION_M365_CLIENT_DOMAINS comma-separated known client domains (the cross-org filter)
# NOTE: migration 0065 is merged but not yet applied to prod - the upsert fails loudly and
# the catch gates it until the orchestrator applies it.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 teams chat' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\teams-chat.task.ps1"' `
#     -Interval Hourly

Import-Module ImperionPipeline
Initialize-ImperionContext

$users = @($env:IMPERION_M365_USERS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$clientDomains = @($env:IMPERION_M365_CLIENT_DOMAINS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($users.Count -eq 0 -or $clientDomains.Count -eq 0) {
    Write-ImperionLog -Level Warn -Source 'm365' -Message 'm365 teams-chat sync skipped: set IMPERION_M365_USERS and IMPERION_M365_CLIENT_DOMAINS.'
    return
}

try {
    Get-ImperionM365TeamsChat -User $users -ClientDomain $clientDomains | Set-ImperionM365TeamsChatToBronze
}
catch {
    Write-ImperionLog -Level Warn -Source 'm365' -Message "m365 teams-chat sync skipped (0065 applied yet?): $($_.Exception.Message)"
}
