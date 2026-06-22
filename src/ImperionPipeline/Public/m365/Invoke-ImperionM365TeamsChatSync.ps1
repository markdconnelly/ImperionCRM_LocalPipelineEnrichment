function Invoke-ImperionM365TeamsChatSync {
    <#
    .SYNOPSIS
        Hourly cross-org Teams chat pull -> bronze (m365_teams_chats, migration 0065).
    .DESCRIPTION
        Promoted from scheduled-tasks/m365/teams-chat.task.ps1 per ADR-0007 (cmdlet-first;
        no loose entry scripts). Composes one get + one post: Get-ImperionM365TeamsChat
        piped to Set-ImperionM365TeamsChatToBronze. Single-tenant against the Imperion
        company tenant (Mark's 2026-06-11 authorization; GDAP fan-out deferred). Read-only
        Graph. Requires Initialize-ImperionContext.

        Configuration (GATED - logs + exits cleanly until set):
          IMPERION_M365_USERS          comma-separated user UPNs whose chats to collect
          IMPERION_M365_CLIENT_DOMAINS comma-separated known client domains (cross-org filter)

        NOTE: migration 0065 is merged but not yet applied to prod - the upsert fails loudly
        and the catch gates it until the orchestrator applies it.
    .EXAMPLE
        Invoke-ImperionM365TeamsChatSync
    #>
    [CmdletBinding()]
    param()

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
}
