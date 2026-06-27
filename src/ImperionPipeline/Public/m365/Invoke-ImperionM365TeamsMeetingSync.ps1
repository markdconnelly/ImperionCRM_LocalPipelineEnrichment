function Invoke-ImperionM365TeamsMeetingSync {
    <#
    .SYNOPSIS
        4-hourly home-tenant Teams meeting pull -> bronze (m365_teams_meetings, migration 0065).
    .DESCRIPTION
        Promoted from scheduled-tasks/m365/teams-meeting.task.ps1 per ADR-0007 (cmdlet-first;
        no loose entry scripts). Composes one get + one post: Get-ImperionM365TeamsMeeting
        piped to Set-ImperionM365TeamsMeetingToBronze. Single-tenant against the Imperion
        company tenant (Mark's 2026-06-11 authorization). Read-only Graph. Requires
        Initialize-ImperionContext.

        CAPTURE MODEL (ADR-0126 / FE #1366, this repo's #380): meetings are pulled from
        Imperion's OWN tenant; the client-scoping filter moves to the silver layer (FE #1369),
        so the collector no longer needs (or accepts) a client-domain list. This removed the
        IMPERION_M365_CLIENT_DOMAINS gate that left the table at 0 rows when unset.

        Configuration (GATED - logs + exits cleanly until set):
          IMPERION_M365_USERS              comma-separated user UPNs whose calendars to collect
          IMPERION_M365_MEETING_SINCE_DAYS look-back window (default 30)

        NOTE: migration 0065 is prod-applied - the upsert fails loudly and the catch gates the
        run only if the table is missing.
    .EXAMPLE
        Invoke-ImperionM365TeamsMeetingSync
    #>
    [CmdletBinding()]
    param()

    $users = @($env:IMPERION_M365_USERS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $sinceDays = if ($env:IMPERION_M365_MEETING_SINCE_DAYS) { [int]$env:IMPERION_M365_MEETING_SINCE_DAYS } else { 30 }

    if ($users.Count -eq 0) {
        Write-ImperionLog -Level Warn -Source 'm365' -Message 'm365 teams-meeting sync skipped: set IMPERION_M365_USERS.'
        return
    }

    try {
        Get-ImperionM365TeamsMeeting -User $users -SinceDays $sinceDays | Set-ImperionM365TeamsMeetingToBronze
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'm365' -Message "m365 teams-meeting sync skipped: $($_.Exception.Message)"
    }
}
