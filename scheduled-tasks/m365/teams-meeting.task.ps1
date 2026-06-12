# m365/teams-meeting - 4-hourly cross-org Teams meeting pull -> bronze (m365_teams_meetings,
# migration 0065). Cadence: Every 4h (scheduled-tasks/README.md). Composes one get + one
# post; keep this short (CLAUDE.md §1). Single-tenant against the Imperion company tenant
# (Mark's 2026-06-11 authorization; GDAP fan-out deferred).
#
# Configuration (GATED - logs + exits cleanly until set):
#   IMPERION_M365_USERS              comma-separated user UPNs whose calendars to collect
#   IMPERION_M365_CLIENT_DOMAINS     comma-separated known client domains (the cross-org filter)
#   IMPERION_M365_MEETING_SINCE_DAYS look-back window (default 30)
# NOTE: migration 0065 is merged but not yet applied to prod - the upsert fails loudly and
# the catch gates it until the orchestrator applies it.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 teams meetings' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\teams-meeting.task.ps1"' `
#     -Interval FourHourly

Import-Module ImperionPipeline
Initialize-ImperionContext

$users = @($env:IMPERION_M365_USERS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$clientDomains = @($env:IMPERION_M365_CLIENT_DOMAINS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$sinceDays = if ($env:IMPERION_M365_MEETING_SINCE_DAYS) { [int]$env:IMPERION_M365_MEETING_SINCE_DAYS } else { 30 }

if ($users.Count -eq 0 -or $clientDomains.Count -eq 0) {
    Write-ImperionLog -Level Warn -Source 'm365' -Message 'm365 teams-meeting sync skipped: set IMPERION_M365_USERS and IMPERION_M365_CLIENT_DOMAINS.'
    return
}

try {
    Get-ImperionM365TeamsMeeting -User $users -ClientDomain $clientDomains -SinceDays $sinceDays | Set-ImperionM365TeamsMeetingToBronze
}
catch {
    Write-ImperionLog -Level Warn -Source 'm365' -Message "m365 teams-meeting sync skipped (0065 applied yet?): $($_.Exception.Message)"
}
