function Get-ImperionScopedInteractionTeams {
    <#
    .SYNOPSIS
        Collect SCOPED Teams chat messages (allowlisted principal ↔ client only) → m365_teams bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the SCOPED interaction capture (issue #199 / epic
        #194 child E, ADR-0022) — the Teams half, paired with Get-ImperionScopedInteractionMail.
        For each CONFIG-DRIVEN allowlisted principal (Derek Rankin / Mark Connelly, read from
        `%ProgramData%\Imperion\interaction-allowlist.json`, never hardcoded) it lists that
        principal's 1:1/group chats (members expanded), keeps ONLY chats where the scope predicate
        holds — an allowlisted principal AND a known CLIENT counterpart (resolved against silver
        `contact`/`account`) are both members — then pulls each in-scope chat's MESSAGES and
        flattens them message-grain. Internal-only and non-client chats are filtered AT COLLECTION,
        before bronze (the enrichment/lawful-basis guardrail, CLAUDE.md §8). Returns rows; does not
        write. Requires Initialize-ImperionContext.

        TARGET: bronze `m365_teams` (front-end-owned schema, ADR-0005 / front-end migration 0120
        `bronze_batch_b` — already merged + prod-applied + verified; lossless envelope, PK
        (tenant_id, source, external_id), source `m365_teams`). external_id = the Graph chatMessage
        id. Flat columns carry the message header + a preview; the full Graph message survives
        lossless in raw_payload.

        SCOPE GATES (all fail soft — log + clean exit, never crash the schedule):
          1. Allowlist config present and non-empty (Resolve-ImperionInteractionAllowlist). Absent →
             dormant; logs and returns. The set changes WITHOUT a code release.
          2. Per-chat: Test-ImperionScopedInteraction over the chat members' addresses.

        AUTH + PROTECTED API: the module's cert-SP app-only Graph token (Get-ImperionGraphToken).
        `/users/{id}/chats` and chat messages are Microsoft PROTECTED APIs — application-permission
        access requires Microsoft's approval form on top of the permission grant (the mail path goes
        first; this stays gated until approval). DORMANT until both consent and protected-API
        approval land (Mark): the Graph call fails loudly and the task's catch logs + exits cleanly.

        CONFIRM BEFORE LIVE USE: the chats `$expand=members` member email path, the chat-messages
        resource path, and the message field names are modeled from the documented API; each flat
        column leads with the documented name, misses land NULL, raw_payload keeps everything. NO
        client data or principal identity is logged (counts only, CLAUDE.md §8).
    .PARAMETER TenantId
        Tenant to authenticate against and stamp on rows; defaults to the partner/company tenant.
    .PARAMETER AllowlistPath
        Optional explicit path to the allowlist json (test / on-demand).
    .PARAMETER Connection
        Optional open Npgsql connection used ONLY to read the silver client-contact set. Opened
        from config + disposed when omitted. The collector never writes here.
    .EXAMPLE
        Get-ImperionScopedInteractionTeams | Set-ImperionScopedInteractionTeamsToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $AllowlistPath,
        $Connection
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    # Gate 1 — the config-driven allowlist.
    $allowedPrincipal = Resolve-ImperionInteractionAllowlist -Path $AllowlistPath
    if (-not $allowedPrincipal -or @($allowedPrincipal).Count -eq 0) {
        Write-ImperionLog -Source 'm365' -Message 'Scoped interaction Teams: no allowlist configured (dormant).'
        return
    }

    $ownsConnection = $false
    $activeConnection = $Connection
    if (-not $activeConnection) { $activeConnection = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $clientSet = Resolve-ImperionClientContactSet -Connection $activeConnection
    }
    finally { if ($ownsConnection) { $activeConnection.Dispose() } }

    $token = Get-ImperionGraphToken -TenantId $TenantId

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($principal in $allowedPrincipal) {
        $chatsUri = 'https://graph.microsoft.com/v1.0/users/{0}/chats?$expand=members' -f [uri]::EscapeDataString($principal)
        $chats = Invoke-ImperionGraphRequest -Uri $chatsUri -AccessToken $token

        foreach ($chat in $chats) {
            $memberEmails = @(Get-ImperionMember $chat 'members') | Where-Object { $_ } |
                ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'email' } | Where-Object { $_ }

            if (-not (Test-ImperionScopedInteraction -Participant @($memberEmails) -AllowedPrincipal $allowedPrincipal -ClientEmail $clientSet.Emails -ClientDomain $clientSet.Domains)) {
                continue
            }

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
