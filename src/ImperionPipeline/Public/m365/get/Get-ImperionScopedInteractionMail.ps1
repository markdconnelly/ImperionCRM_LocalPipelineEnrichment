function Get-ImperionScopedInteractionMail {
    <#
    .SYNOPSIS
        Collect SCOPED mail (allowlisted principal ↔ client only) and flatten to m365_email bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the SCOPED interaction capture (issue #199 / epic
        #194 child E, ADR-0022). It is the tightly-scoped successor to the broad
        Get-ImperionM365Mail (domain cross-org filter → m365_mail_messages, migration 0065): this
        collector captures ONLY message-grain mail where a CONFIG-DRIVEN allowlisted principal
        (Derek Rankin / Mark Connelly — read from `%ProgramData%\Imperion\interaction-allowlist.json`,
        never hardcoded) AND a known CLIENT counterpart (resolved against silver `contact`/`account`)
        are both participants. Internal-only threads and threads with non-client external parties
        are filtered AT COLLECTION, before anything lands in bronze (the enrichment/lawful-basis
        guardrail, CLAUDE.md §8). Returns rows; does not write. Requires Initialize-ImperionContext.

        TARGET: bronze `m365_email` (front-end-owned schema, ADR-0005 / front-end migration 0120
        `bronze_batch_b` — already merged + prod-applied + verified; lossless envelope, PK
        (tenant_id, source, external_id), source `m365_email`). external_id = the Graph message id.
        Flat columns carry the message header + a server-queryable preview; the full Graph message
        survives lossless in raw_payload. NOTE: this is MESSAGE grain (`/messages`), distinct from
        the older thread-grain m365_mail_messages collector — both can coexist.

        SCOPE GATES (all fail soft — log + clean exit, never crash the schedule):
          1. Allowlist config present and non-empty (Resolve-ImperionInteractionAllowlist). Absent →
             nothing to capture; logs the dormant state and returns. The set changes WITHOUT a code
             release.
          2. Per-message: Test-ImperionScopedInteraction over the participant addresses — keeps the
             message ONLY when an allowlisted principal AND a client counterpart are both present.

        AUTH: the module's cert-SP app-only Graph token (Get-ImperionGraphToken), single-tenant
        against the Imperion company tenant by default (Mark's 2026-06-11 authorization); the
        per-client onboarding-app fan-out (pipeline ADR-0018) is supported via -TenantId but
        deferred. DORMANT until Graph mail read consent is provisioned (Mark): with no allowlist
        and/or no Graph access, the collector logs and exits cleanly.

        CONFIRM BEFORE LIVE USE: the Graph `/messages` $select fields, the receivedDateTime filter,
        and the direction heuristic are modeled from the documented API. Each flat column leads with
        the documented name; an unmatched value lands NULL and nothing is lost (full raw_payload).
        NO client data or principal identity is logged (counts only, CLAUDE.md §8).
    .PARAMETER TenantId
        Tenant to authenticate against and stamp on rows; defaults to the partner/company tenant.
    .PARAMETER SinceDays
        Look-back window on receivedDateTime. Default 7.
    .PARAMETER AllowlistPath
        Optional explicit path to the allowlist json (test / on-demand). Defaults to env /
        %ProgramData%\Imperion\interaction-allowlist.json.
    .PARAMETER Connection
        Optional open Npgsql connection used ONLY to read the silver client-contact set. Opened
        from config + disposed when omitted. The collector never writes here.
    .EXAMPLE
        Get-ImperionScopedInteractionMail | Set-ImperionScopedInteractionMailToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [int] $SinceDays = 7,
        [string] $AllowlistPath,
        $Connection
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    # Gate 1 — the config-driven allowlist. No principals configured = nothing to capture.
    $allowedPrincipal = Resolve-ImperionInteractionAllowlist -Path $AllowlistPath
    if (-not $allowedPrincipal -or @($allowedPrincipal).Count -eq 0) {
        Write-ImperionLog -Source 'm365' -Message 'Scoped interaction mail: no allowlist configured (dormant).'
        return
    }

    # Resolve the client counterpart set from silver (read-only).
    $ownsConnection = $false
    $activeConnection = $Connection
    if (-not $activeConnection) { $activeConnection = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $clientSet = Resolve-ImperionClientContactSet -Connection $activeConnection
    }
    finally { if ($ownsConnection) { $activeConnection.Dispose() } }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $sinceIso = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $select = 'id,subject,bodyPreview,from,toRecipients,ccRecipients,receivedDateTime,sentDateTime,conversationId,hasAttachments,webLink'

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($principal in $allowedPrincipal) {
        $uri = 'https://graph.microsoft.com/v1.0/users/{0}/messages?$filter=receivedDateTime ge {1}&$select={2}&$top=50' -f [uri]::EscapeDataString($principal), $sinceIso, $select
        $messages = Invoke-ImperionGraphRequest -Uri $uri -AccessToken $token

        foreach ($message in $messages) {
            $participants = [System.Collections.Generic.List[string]]::new()
            $fromAddress = Get-ImperionPropertyPath -InputObject $message -Path 'from.emailAddress.address'
            if ($fromAddress) { $participants.Add($fromAddress) }
            foreach ($recipientProp in 'toRecipients', 'ccRecipients') {
                @(Get-ImperionMember $message $recipientProp) | Where-Object { $_ } |
                    ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'emailAddress.address' } |
                    Where-Object { $_ } | ForEach-Object { $participants.Add($_) }
            }

            if (Test-ImperionScopedInteraction -Participant $participants.ToArray() -AllowedPrincipal $allowedPrincipal -ClientEmail $clientSet.Emails -ClientDomain $clientSet.Domains) {
                # Direction is relative to the captured principal's mailbox: a message the
                # principal sent is outbound, otherwise inbound.
                $direction = if ($fromAddress -and "$fromAddress".Trim().ToLowerInvariant() -eq "$principal".Trim().ToLowerInvariant()) { 'outbound' } else { 'inbound' }
                $message | Add-Member -NotePropertyName '_imperionMailboxOwner' -NotePropertyValue $principal -Force
                $message | Add-Member -NotePropertyName '_imperionDirection' -NotePropertyValue $direction -Force
                $kept.Add($message)
            }
        }
    }

    $map = [ordered]@{
        message_id      = 'id'
        conversation_id = 'conversationId'
        subject         = 'subject'
        preview         = 'bodyPreview'
        from_address    = { param($m) Get-ImperionPropertyPath -InputObject $m -Path 'from.emailAddress.address' }
        to_recipients   = { param($m) (@(Get-ImperionMember $m 'toRecipients') | Where-Object { $_ } | ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'emailAddress.address' }) | Join-ImperionValues }
        direction       = { param($m) Get-ImperionMember $m '_imperionDirection' }
        sent_at         = { param($m) $v = Get-ImperionPropertyPath -InputObject $m -Path 'sentDateTime'; if ($v) { $v } else { Get-ImperionPropertyPath -InputObject $m -Path 'receivedDateTime' } }
        has_attachments = 'hasAttachments'
        mailbox_owner   = { param($m) Get-ImperionMember $m '_imperionMailboxOwner' }
    }

    $kept | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365_email' -TenantId $TenantId -ExternalIdProperty 'id'
}
