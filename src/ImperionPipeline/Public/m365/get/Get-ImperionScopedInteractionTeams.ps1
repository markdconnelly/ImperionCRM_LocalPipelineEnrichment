function Get-ImperionScopedInteractionTeams {
    <#
    .SYNOPSIS
        Collect message-grain Teams chat messages from the allowlisted Imperion principals → m365_teams bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the home-tenant communications capture (issue #199 /
        epic #194 child E, ADR-0022; revived per front-end ADR-0126 / FE #1366, this repo's #380) —
        the Teams half, paired with Get-ImperionScopedInteractionMail. For each CONFIG-DRIVEN
        allowlisted principal (Derek Rankin / Mark Connelly, read from
        `%ProgramData%\Imperion\interaction-allowlist.json`, never hardcoded) it lists that
        principal's 1:1/group chats (members expanded), pulls EVERY chat's MESSAGES, and flattens
        them message-grain. Returns rows; does not write. Requires Initialize-ImperionContext.

        CAPTURE MODEL (ADR-0126): communications are pulled from Imperion's OWN tenant and the
        client-scoping filter is applied LATER, at the silver layer, against `account_domain` +
        onboarded contacts — front-end #1369. This collector therefore does NOT filter at
        collection: that was the bug behind the 0-row prod state (#380) — the collection-time
        `Test-ImperionScopedInteraction` client gate dropped every chat whenever the silver client
        set was empty (`account_domain` is unpopulated in prod). Over-collect at bronze; narrow at
        silver (CLAUDE.md §5 bronze rule). The allowlist now selects WHICH PRINCIPALS' chats to
        pull, not which chats to keep.

        TARGET: bronze `m365_teams` (front-end-owned schema, ADR-0005 / front-end migration 0120
        `bronze_batch_b` — already merged + prod-applied + verified; lossless envelope, PK
        (tenant_id, source, external_id), source `m365_teams`). external_id = the Graph chatMessage
        id. Flat columns carry the message header + a preview; the full Graph message survives
        lossless in raw_payload.

        GATE (fails soft — log + clean exit, never crash the schedule):
          * Allowlist config present and non-empty (Resolve-ImperionInteractionAllowlist). Absent →
            no principals to enumerate → dormant; logs and returns. The set changes WITHOUT a code
            release.

        AUTH + PROTECTED API: the module's cert-SP app-only Graph token (Get-ImperionGraphToken).
        `/users/{id}/chats` and chat messages are Microsoft PROTECTED APIs — application-permission
        access requires Microsoft's approval form on top of the permission grant (the mail path goes
        first; this stays gated until approval). DORMANT until both consent and protected-API
        approval land (Mark): the Graph call fails loudly and the task's catch logs + exits cleanly.

        CONFIRM BEFORE LIVE USE: the chats `$expand=members` member email path, the chat-messages
        resource path, and the message field names are modeled from the documented API; each flat
        column leads with the documented name, misses land NULL, raw_payload keeps everything. NO
        message content or participant identity is logged (counts only, CLAUDE.md §8).
    .PARAMETER TenantId
        Tenant to authenticate against and stamp on rows; defaults to the partner/company tenant.
    .PARAMETER AllowlistPath
        Optional explicit path to the allowlist json (test / on-demand).
    .PARAMETER Connection
        Accepted for call-shape compatibility with the task pipeline; unused (client scoping moved
        to the silver layer, FE #1369). The collector never reads or writes the DB.
    .EXAMPLE
        Get-ImperionScopedInteractionTeams | Set-ImperionScopedInteractionTeamsToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Connection',
        Justification = 'Kept for call-shape stability with the task pipeline; client scoping moved to silver (FE #1369).')]
    param(
        [string] $TenantId,
        [string] $AllowlistPath,
        $Connection
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    # Gate — the config-driven allowlist names whose chats to pull. No principals = nothing to do.
    $allowedPrincipal = Resolve-ImperionInteractionAllowlist -Path $AllowlistPath
    if (-not $allowedPrincipal -or @($allowedPrincipal).Count -eq 0) {
        Write-ImperionLog -Source 'm365' -Message 'Scoped interaction Teams: no allowlist configured (dormant).'
        return
    }

    $token = Get-ImperionGraphToken -TenantId $TenantId

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($principal in $allowedPrincipal) {
        $chatsUri = 'https://graph.microsoft.com/v1.0/users/{0}/chats?$expand=members' -f [uri]::EscapeDataString($principal)
        $chats = Invoke-ImperionGraphRequest -Uri $chatsUri -AccessToken $token

        foreach ($chat in $chats) {
            $memberEmails = @(Get-ImperionMember $chat 'members') | Where-Object { $_ } |
                ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'email' } | Where-Object { $_ }

            # ADR-0126: keep every home-tenant chat; the client filter is a silver concern (FE #1369).
            $chatId = Get-ImperionMember $chat 'id'
            $participantList = (@($memberEmails) | Where-Object { $_ }) | Join-ImperionValues
            $messagesUri = 'https://graph.microsoft.com/v1.0/chats/{0}/messages' -f [uri]::EscapeDataString([string]$chatId)
            $messages = Invoke-ImperionGraphRequest -Uri $messagesUri -AccessToken $token

            foreach ($message in $messages) {
                $authorAddress = Get-ImperionPropertyPath -InputObject $message -Path 'from.user.email'
                if (-not $authorAddress) { $authorAddress = Get-ImperionPropertyPath -InputObject $message -Path 'from.user.displayName' }
                $direction = if ($authorAddress -and ("$authorAddress".Trim().ToLowerInvariant() -in @($allowedPrincipal))) { 'outbound' } else { 'inbound' }

                $message | Add-Member -NotePropertyName '_imperionChatId' -NotePropertyValue $chatId -Force
                $message | Add-Member -NotePropertyName '_imperionParticipants' -NotePropertyValue $participantList -Force
                $message | Add-Member -NotePropertyName '_imperionFromUser' -NotePropertyValue $authorAddress -Force
                $message | Add-Member -NotePropertyName '_imperionDirection' -NotePropertyValue $direction -Force
                $message | Add-Member -NotePropertyName '_imperionCapturedUser' -NotePropertyValue $principal -Force
                $kept.Add($message)
            }
        }
    }

    $map = [ordered]@{
        message_id      = 'id'
        conversation_id = { param($m) Get-ImperionMember $m '_imperionChatId' }
        preview         = { param($m) Get-ImperionPropertyPath -InputObject $m -Path 'body.content' }
        from_user       = { param($m) Get-ImperionMember $m '_imperionFromUser' }
        participants    = { param($m) Get-ImperionMember $m '_imperionParticipants' }
        direction       = { param($m) Get-ImperionMember $m '_imperionDirection' }
        message_type    = { param($m) $v = Get-ImperionMember $m 'messageType'; if ($v) { $v } else { 'message' } }
        sent_at         = { param($m) $v = Get-ImperionMember $m 'createdDateTime'; if ($v) { $v } else { Get-ImperionMember $m 'lastModifiedDateTime' } }
        has_attachments = { param($m) [bool](@(Get-ImperionMember $m 'attachments' | Where-Object { $_ }).Count) }
        captured_user   = { param($m) Get-ImperionMember $m '_imperionCapturedUser' }
    }

    $kept | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365_teams' -TenantId $TenantId -ExternalIdProperty 'id'
}
