# m365/mail - hourly cross-org mail pull -> bronze (m365_mail_messages, migration 0065).
# Cadence: Hourly (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Single-tenant against the Imperion company tenant (Mark's 2026-06-11
# authorization; GDAP fan-out deferred — assume clients grant data in the same formats).
#
# Configuration (GATED - logs + exits cleanly until set):
#   IMPERION_M365_MAILBOXES      comma-separated mailbox UPNs to collect
#   IMPERION_M365_CLIENT_DOMAINS comma-separated known client domains (the cross-org filter)
#   IMPERION_M365_MAIL_SINCE_DAYS look-back window (default 7)
# NOTE: migration 0065 is merged but not yet applied to prod - the upsert fails loudly and
# the catch gates it until the orchestrator applies it.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 mail' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\mail.task.ps1"' `
#     -Interval Hourly

Import-Module ImperionPipeline
Initialize-ImperionContext

$mailboxes = @($env:IMPERION_M365_MAILBOXES -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$clientDomains = @($env:IMPERION_M365_CLIENT_DOMAINS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$sinceDays = if ($env:IMPERION_M365_MAIL_SINCE_DAYS) { [int]$env:IMPERION_M365_MAIL_SINCE_DAYS } else { 7 }

if ($mailboxes.Count -eq 0 -or $clientDomains.Count -eq 0) {
    Write-ImperionLog -Level Warn -Source 'm365' -Message 'm365 mail sync skipped: set IMPERION_M365_MAILBOXES and IMPERION_M365_CLIENT_DOMAINS.'
    return
}

try {
    Get-ImperionM365Mail -Mailbox $mailboxes -ClientDomain $clientDomains -SinceDays $sinceDays | Set-ImperionM365MailToBronze
}
catch {
    Write-ImperionLog -Level Warn -Source 'm365' -Message "m365 mail sync skipped (0065 applied yet?): $($_.Exception.Message)"
}
