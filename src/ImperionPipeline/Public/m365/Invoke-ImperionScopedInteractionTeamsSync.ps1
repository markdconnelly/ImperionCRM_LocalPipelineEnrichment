function Invoke-ImperionScopedInteractionTeamsSync {
    <#
    .SYNOPSIS
        Hourly SCOPED Teams chat pull -> bronze (m365_teams).
    .DESCRIPTION
        Promoted from scheduled-tasks/m365/scoped-interaction-teams.task.ps1 per ADR-0007
        (cmdlet-first; no loose entry scripts). Composes one get + one post:
        Get-ImperionScopedInteractionTeams piped to Set-ImperionScopedInteractionTeamsToBronze.
        Requires Initialize-ImperionContext.

        Captures ONLY message-grain chat messages from in-scope chats: a CONFIG-DRIVEN
        allowlisted principal (Derek/Mark, read from
        %ProgramData%\Imperion\interaction-allowlist.json - never hardcoded) AND a known
        client counterpart (silver contact/account) are both members; internal-only +
        non-client chats are filtered AT COLLECTION, before bronze (lawful basis,
        CLAUDE.md §8). MESSAGE-grain (issue #199, ADR-0022).

        Auth: the module's cert-SP read-only Graph token - no new app reg, no new secret. The
        front-end bronze migration 0120 (m365_teams) is PROD-APPLIED; the post writer fails
        loudly if absent (ADR-0005).

        TRIPLE-GATED / DORMANT: (1) the allowlist json, (2) chat read consent, (3) Microsoft
        PROTECTED-API approval for /chats + chat messages (the mail path goes first). No
        allowlist -> log + return nothing; no access/approval -> the Graph call fails loudly
        and the catch below logs + exits cleanly. The task never crashes the schedule.
        Registration is deferred to server bringup (#102).
    .EXAMPLE
        Invoke-ImperionScopedInteractionTeamsSync
    #>
    [CmdletBinding()]
    param()

    try {
        Get-ImperionScopedInteractionTeams | Set-ImperionScopedInteractionTeamsToBronze
    }
    catch {
        # Allowlist / consent / protected-API / schema gate: must not crash the schedule - log loudly and
        # exit; the operator clears the gate and the next run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'm365' -Message "Scoped interaction Teams sync skipped: $($_.Exception.Message)"
    }
}
