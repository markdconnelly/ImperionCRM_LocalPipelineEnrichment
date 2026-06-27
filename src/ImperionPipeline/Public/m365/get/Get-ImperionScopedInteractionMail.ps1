function Get-ImperionScopedInteractionMail {
    <#
    .SYNOPSIS
        Collect message-grain mail from the allowlisted Imperion mailboxes and flatten to m365_email bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the home-tenant communications capture (issue #199 /
        epic #194 child E, ADR-0022; revived per front-end ADR-0126 / FE #1366, this repo's #380).
        It pulls message-grain mail (`/messages`) from each CONFIG-DRIVEN allowlisted mailbox
        (Derek Rankin / Mark Connelly — read from `%ProgramData%\Imperion\interaction-allowlist.json`,
        never hardcoded) and flattens EVERY message to the m365_email bronze envelope. Returns rows;
        does not write. Requires Initialize-ImperionContext.

        CAPTURE MODEL (ADR-0126): communications are pulled from Imperion's OWN tenant and the
        client-scoping filter (keep only direct client↔employee threads) is applied LATER, at the
        silver layer, against `account_domain` + onboarded contacts — front-end #1369. This
        collector therefore does NOT filter at collection: that was the bug behind the 0-row prod
        state (#380). The collection-time `Test-ImperionScopedInteraction` client gate dropped every
        message whenever the silver client set was empty (`account_domain` is unpopulated in prod),
        so a fully-consented collector still landed zero rows. Over-collect at bronze; narrow at
        silver (CLAUDE.md §5 bronze rule). The allowlist now selects WHICH MAILBOXES to pull, not
        which messages to keep.

        TARGET: bronze `m365_email` (front-end-owned schema, ADR-0005 / front-end migration 0120
        `bronze_batch_b` — already merged + prod-applied + verified; lossless envelope, PK
        (tenant_id, source, external_id), source `m365_email`). external_id = the Graph message id.
        Flat columns carry the message header + a server-queryable preview; the full Graph message
        survives lossless in raw_payload. NOTE: this is MESSAGE grain (`/messages`), distinct from
        the older thread-grain m365_mail_messages collector — both can coexist.

        GATE (fails soft — log + clean exit, never crash the schedule):
          * Allowlist config present and non-empty (Resolve-ImperionInteractionAllowlist). Absent →
            no mailboxes to enumerate → logs the dormant state and returns. The set changes WITHOUT
            a code release.

        AUTH: the module's cert-SP app-only Graph token (Get-ImperionGraphToken), single-tenant
        against the Imperion company tenant by default (Mark's 2026-06-11 authorization); the
        per-client onboarding-app fan-out (pipeline ADR-0018) is supported via -TenantId but
        deferred. DORMANT until Graph Mail.Read consent is provisioned (Mark): with no allowlist
        and/or no Graph access, the collector logs and exits cleanly.

        CONFIRM BEFORE LIVE USE: the Graph `/messages` $select fields, the receivedDateTime filter,
        and the direction heuristic are modeled from the documented API. Each flat column leads with
        the documented name; an unmatched value lands NULL and nothing is lost (full raw_payload).
        NO message content or address is logged (counts only, CLAUDE.md §8).
    .PARAMETER TenantId
        Tenant to authenticate against and stamp on rows; defaults to the partner/company tenant.
    .PARAMETER SinceDays
        Look-back window on receivedDateTime. Default 7.
    .PARAMETER AllowlistPath
        Optional explicit path to the allowlist json (test / on-demand). Defaults to env /
        %ProgramData%\Imperion\interaction-allowlist.json.
    .PARAMETER Connection
        Accepted for call-shape compatibility with the task pipeline; unused (client scoping moved
        to the silver layer, FE #1369). The collector never reads or writes the DB.
    .EXAMPLE
        Get-ImperionScopedInteractionMail | Set-ImperionScopedInteractionMailToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Connection',
        Justification = 'Kept for call-shape stability with the task pipeline; client scoping moved to silver (FE #1369).')]
    param(
        [string] $TenantId,
        [int] $SinceDays = 7,
        [string] $AllowlistPath,
        $Connection
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    # Gate — the config-driven allowlist names which mailboxes to pull. No mailboxes = nothing to do.
    $allowedPrincipal = Resolve-ImperionInteractionAllowlist -Path $AllowlistPath
    if (-not $allowedPrincipal -or @($allowedPrincipal).Count -eq 0) {
        Write-ImperionLog -Source 'm365' -Message 'Scoped interaction mail: no allowlist configured (dormant).'
        return
    }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $sinceIso = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $select = 'id,subject,bodyPreview,from,toRecipients,ccRecipients,receivedDateTime,sentDateTime,conversationId,hasAttachments,webLink'

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($principal in $allowedPrincipal) {
        $uri = 'https://graph.microsoft.com/v1.0/users/{0}/messages?$filter=receivedDateTime ge {1}&$select={2}&$top=50' -f [uri]::EscapeDataString($principal), $sinceIso, $select
        $messages = Invoke-ImperionGraphRequest -Uri $uri -AccessToken $token

        foreach ($message in $messages) {
            $fromAddress = Get-ImperionPropertyPath -InputObject $message -Path 'from.emailAddress.address'

            # ADR-0126: keep every home-tenant message; the client filter is a silver concern (FE #1369).
            # Direction is relative to the captured principal's mailbox: a message the principal
            # sent is outbound, otherwise inbound.
            $direction = if ($fromAddress -and "$fromAddress".Trim().ToLowerInvariant() -eq "$principal".Trim().ToLowerInvariant()) { 'outbound' } else { 'inbound' }
            $message | Add-Member -NotePropertyName '_imperionMailboxOwner' -NotePropertyValue $principal -Force
            $message | Add-Member -NotePropertyName '_imperionDirection' -NotePropertyValue $direction -Force
            $kept.Add($message)
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
