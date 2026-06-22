function Invoke-ImperionScopedInteractionMailSync {
    <#
    .SYNOPSIS
        Hourly SCOPED mail pull -> bronze (m365_email).
    .DESCRIPTION
        Promoted from scheduled-tasks/m365/scoped-interaction-mail.task.ps1 per ADR-0007
        (cmdlet-first; no loose entry scripts). Composes one get + one post:
        Get-ImperionScopedInteractionMail piped to Set-ImperionScopedInteractionMailToBronze.
        Requires Initialize-ImperionContext.

        Captures ONLY message-grain mail where a CONFIG-DRIVEN allowlisted principal
        (Derek/Mark, read from %ProgramData%\Imperion\interaction-allowlist.json - never
        hardcoded) AND a known client counterpart (resolved against silver contact/account)
        are both participants; internal-only + non-client traffic is filtered AT COLLECTION,
        before bronze (lawful basis, CLAUDE.md §8). MESSAGE-grain - distinct from the
        cross-org m365_mail_messages (migration 0065) path; both coexist (issue #199,
        ADR-0022).

        Auth: the module's cert-SP read-only Graph token (Get-ImperionGraphToken) - no new
        app reg, no new secret. The front-end bronze migration 0120 (m365_email) is
        PROD-APPLIED; if the table were absent the post writer fails loudly (ADR-0005).

        DORMANT until the allowlist json + Graph Mail.Read consent are provisioned (Mark): no
        allowlist -> the collector logs + returns nothing; no Graph access -> the catch below
        logs + exits cleanly. The task never crashes the schedule. Registration is deferred
        to server bringup (#102).
    .EXAMPLE
        Invoke-ImperionScopedInteractionMailSync
    #>
    [CmdletBinding()]
    param()

    try {
        Get-ImperionScopedInteractionMail | Set-ImperionScopedInteractionMailToBronze
    }
    catch {
        # Allowlist / consent / schema gate: missing config, no Graph access, or a missing m365_email
        # table must not crash the schedule - log loudly and exit; the operator provisions consent/config
        # and the next run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'm365' -Message "Scoped interaction mail sync skipped: $($_.Exception.Message)"
    }
}
