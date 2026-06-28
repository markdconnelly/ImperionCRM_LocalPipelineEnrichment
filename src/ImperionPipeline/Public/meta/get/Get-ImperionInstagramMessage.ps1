function Get-ImperionInstagramMessage {
    <#
    .SYNOPSIS
        Collect Instagram Direct Messages and flatten ONE row per message to instagram_messages bronze.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source — the IG twin of
        Get-ImperionMetaConversation (LocalPipeline #361; front-end migration 0207;
        ADR-0124 Social Media plane). IG Direct Messages are reached THROUGH the linked
        Facebook Page's inbox with `platform=instagram` on /{PageId}/conversations — the
        same Page-token requirement as the Messenger inbox (the system-user token is
        rejected); when -PageToken is omitted it is resolved via Get-ImperionMetaPageToken.
        The IG business-account (IG user) id is resolved once via
        /{PageId}?fields=instagram_business_account (override with -IgUserId to skip the
        hop) and stamped on every row. Emits one flat row per MESSAGE (external_id = the
        message id) shaped to the instagram_messages column set (front-end migration 0207).
        to_* is the first non-IG-account recipient.

        DM SENDERS BECOME LEADS in silver (lead_hook kind instagram_dm, the 0206 contract,
        the facebook_dm precedent) — this carries message text and IG handles. Bronze
        custody only; never log row contents. Returns rows; does not write. Requires
        Initialize-ImperionContext.

        DORMANT until conn-company-meta is seeded AND the IG messaging scope
        (instagram_manage_messages) is approved at Meta App Review — same gate as the
        outbound IG reply (ImperionCRM_Backend #419).

        ASSUMED-FIELD-NAMES caveat: fields follow Meta's published IG-messaging reference;
        IG participants carry `username` rather than `name`. Unreadable fields land NULL in
        flat columns and survive in raw_payload. Verify against a live first run.
    .PARAMETER PageId
        The Facebook Page id whose linked IG inbox to collect (used to resolve the IG user).
    .PARAMETER PageToken
        Page access token override. Defaults to Get-ImperionMetaPageToken -PageId $PageId.
    .PARAMETER IgUserId
        Instagram business-account (IG user) id override — skips the Page hop. Stamped on
        each row as ig_user_id (the inbox owner; the "page" side of a DM).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user token override (used only to resolve the page token / IG user).
    .PARAMETER MaxPages
        Conversation-paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionInstagramMessage -PageId '123456789' | Set-ImperionInstagramMessageToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $PageId,
        [string] $PageToken,
        [string] $IgUserId,
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    if (-not $PageToken) { $PageToken = Get-ImperionMetaPageToken -PageId $PageId -Token $Token }

    # Resolve the IG business-account once (the inbox owner). An unlinked Page is a
    # configuration state, not an error: warn and return nothing.
    if (-not $IgUserId) {
        $page = @(Invoke-ImperionMetaRequest -Token $PageToken `
                -Uri ('{0}?fields=instagram_business_account' -f [uri]::EscapeDataString($PageId))) |
            Select-Object -First 1
        $IgUserId = if ($null -ne $page) {
            [string](Get-ImperionPropertyPath -InputObject $page -Path 'instagram_business_account.id')
        }
        if (-not $IgUserId) {
            Write-ImperionLog -Level Warn -Source 'meta' -Message "Page $PageId has no linked instagram_business_account - skipping IG DMs."
            return
        }
    }

    # platform=instagram routes the conversations edge to the IG inbox (same Page-token hop
    # as the Messenger inbox). Participants/messages carry IG-scoped ids + usernames.
    $fields = 'participants,updated_time,messages.limit(100){message,from,to,created_time}'
    $uri = '{0}/conversations?platform=instagram&fields={1}&limit=50' -f [uri]::EscapeDataString($PageId), $fields
    $conversations = @(Invoke-ImperionMetaRequest -Token $PageToken -Uri $uri -MaxPages $MaxPages)

    $flatMessages = [System.Collections.Generic.List[object]]::new()
    foreach ($conversation in $conversations) {
        $conversationId = [string](Get-ImperionMember $conversation 'id')
        $messages = @(Get-ImperionPropertyPath -InputObject $conversation -Path 'messages.data')
        foreach ($message in $messages) {
            if ($null -eq $message) { continue }
            # to.data is the recipient list; the IG account itself is usually among them —
            # the contract row wants the first recipient that is NOT the IG account.
            $recipients = @(Get-ImperionPropertyPath -InputObject $message -Path 'to.data') | Where-Object { $_ }
            $recipient = @($recipients | Where-Object { [string](Get-ImperionMember $_ 'id') -ne $IgUserId }) |
                Select-Object -First 1
            if (-not $recipient) { $recipient = $recipients | Select-Object -First 1 }

            $message | Add-Member -NotePropertyName '_imperionConversationId' -NotePropertyValue $conversationId -Force
            $message | Add-Member -NotePropertyName '_imperionIgUserId' -NotePropertyValue $IgUserId -Force
            $message | Add-Member -NotePropertyName '_imperionToId' -NotePropertyValue ([string](Get-ImperionMember $recipient 'id')) -Force
            $message | Add-Member -NotePropertyName '_imperionToUsername' -NotePropertyValue ([string](Get-ImperionMember $recipient 'username')) -Force
            $flatMessages.Add($message)
        }
    }

    $map = [ordered]@{
        conversation_id = '_imperionConversationId'
        ig_user_id      = '_imperionIgUserId'
        message         = 'message'
        from_id         = 'from.id'
        from_username   = 'from.username'
        to_id           = '_imperionToId'
        to_username     = '_imperionToUsername'
        created_time    = 'created_time'
    }

    $flatMessages | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'instagram' -TenantId $TenantId -ExternalIdProperty 'id'
}
