function Invoke-ImperionM365TeamsMeetingSync {
    <#
    .SYNOPSIS
        4-hourly cross-org Teams meeting pull -> bronze (m365_teams_meetings, migration 0065).
    .DESCRIPTION
        Promoted from scheduled-tasks/m365/teams-meeting.task.ps1 per ADR-0007 (cmdlet-first;
        no loose entry scripts). Composes one get + one post: Get-ImperionM365TeamsMeeting
        piped to Set-ImperionM365TeamsMeetingToBronze. Single-tenant against the Imperion
        company tenant (Mark's 2026-06-11 authorization; GDAP fan-out deferred). Read-only
        Graph. Requires Initialize-ImperionContext.

        Configuration (GATED - logs + exits cleanly until set):
          IMPERION_M365_USERS              comma-separated user UPNs whose calendars to collect
          IMPERION_M365_CLIENT_DOMAINS     comma-separated known client domains (cross-org filter)
          IMPERION_M365_MEETING_SINCE_DAYS look-back window (default 30)

        NOTE: migration 0065 is merged but not yet applied to prod - the upsert fails loudly
        and the catch gates it until the orchestrator applies it.
    .EXAMPLE
        Invoke-ImperionM365TeamsMeetingSync
    #>
    [CmdletBinding()]
    param()

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
}
