function Get-ImperionMetaConversation {
    <#
    .SYNOPSIS
        Collect page-inbox (Messenger) conversations and flatten ONE row per message to facebook_messages bronze.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source, issue #126. The
        /conversations edge requires a PAGE access token (the system-user token is
        rejected) — when -PageToken is omitted it is resolved via
        Get-ImperionMetaPageToken using the system-user token. Pages
        /{PageId}/conversations with the nested messages field and emits one flat row
        per MESSAGE (external_id = the message id) shaped to the facebook_messages
        column set (front-end migration 0075). to_* is the first non-page recipient.

        DM SENDERS BECOME LEADS in silver (lead_hook kind facebook_dm, the 0075
        contract) — this is the highest-PII collector in the meta set; payloads carry
        message text and sender names. Bronze custody only; never log row contents.
        Returns rows; does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat: fields follow Meta's published conversation/message
        reference (pages_messaging scope); unreadable fields land NULL in flat columns
        and survive in raw_payload. Verify against a live first run.
    .PARAMETER PageId
        The Facebook Page id whose inbox to collect (stamped onto each row as page_id).
    .PARAMETER PageToken
        Page access token override. Defaults to Get-ImperionMetaPageToken -PageId $PageId.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user token override (used only to resolve the page token).
    .PARAMETER MaxPages
        Conversation-paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionMetaConversation -PageId '123456789' | Set-ImperionMetaMessageToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $PageId,
        [string] $PageToken,
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    if (-not $PageToken) { $PageToken = Get-ImperionMetaPageToken -PageId $PageId -Token $Token }

    $fields = 'participants,updated_time,messages.limit(100){message,from,to,created_time}'
    $uri = '{0}/conversations?fields={1}&limit=50' -f [uri]::EscapeDataString($PageId), $fields
    $conversations = @(Invoke-ImperionMetaRequest -Token $PageToken -Uri $uri -MaxPages $MaxPages)

    $flatMessages = [System.Collections.Generic.List[object]]::new()
    foreach ($conversation in $conversations) {
        $conversationId = [string](Get-ImperionMember $conversation 'id')
        $messages = @(Get-ImperionPropertyPath -InputObject $conversation -Path 'messages.data')
        foreach ($message in $messages) {
            if ($null -eq $message) { continue }
            # to.data is the recipient list; the page itself is usually among them —
            # the contract row wants the first NON-page recipient (else the first).
            $recipients = @(Get-ImperionPropertyPath -InputObject $message -Path 'to.data') | Where-Object { $_ }
            $recipient = @($recipients | Where-Object { [string](Get-ImperionMember $_ 'id') -ne $PageId }) |
                Select-Object -First 1
            if (-not $recipient) { $recipient = $recipients | Select-Object -First 1 }

            $message | Add-Member -NotePropertyName '_imperionConversationId' -NotePropertyValue $conversationId -Force
            $message | Add-Member -NotePropertyName '_imperionPageId' -NotePropertyValue $PageId -Force
            $message | Add-Member -NotePropertyName '_imperionToId' -NotePropertyValue ([string](Get-ImperionMember $recipient 'id')) -Force
            $message | Add-Member -NotePropertyName '_imperionToName' -NotePropertyValue ([string](Get-ImperionMember $recipient 'name')) -Force
            $flatMessages.Add($message)
        }
    }

    $map = [ordered]@{
        conversation_id = '_imperionConversationId'
        page_id         = '_imperionPageId'
        message         = 'message'
        from_id         = 'from.id'
        from_name       = 'from.name'
        to_id           = '_imperionToId'
        to_name         = '_imperionToName'
        created_time    = 'created_time'
    }

    $flatMessages | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'facebook' -TenantId $TenantId -ExternalIdProperty 'id'
}
