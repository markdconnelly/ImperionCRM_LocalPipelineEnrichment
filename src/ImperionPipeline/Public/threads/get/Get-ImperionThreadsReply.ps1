function Get-ImperionThreadsReply {
    <#
    .SYNOPSIS
        Collect replies on our Threads posts and flatten them to threads_replies bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the `threads` source (LocalPipeline #356,
        front-end Threads epic #1334 / ADR-0125). Takes our own post ids from the pipeline
        (the rows Get-ImperionThreadsPost emits bind by their external_id property) or an
        explicit -PostId array, pages `/{thread-id}/replies` per post (the conversation
        replies under one of our posts), and flattens to the threads_replies column set
        (front-end migration 0208). Replies are TIMELINE rows in silver — interaction kind
        `social_comment`, direction by author (ours = outbound, theirs = inbound), never
        leads (the Threads-mentions-are-of-us contract, ADR-0125 D2). Returns rows; does not
        write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat (the Get-ImperionMetaPostComment precedent): fields follow
        the published Threads reply reference; anything the token cannot read lands NULL in
        the flat column and survives in raw_payload. Verify against a live first run.
    .PARAMETER PostId
        Our Threads post ids to collect replies for. Accepts pipeline input — including the
        flattened post rows themselves (binds external_id by property name).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Threads token override. Defaults to the credential-registry resolution
        (Resolve-ImperionThreadsToken, ADR-0103).
    .PARAMETER MaxPages
        Paging cap per post forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionThreadsPost | Get-ImperionThreadsReply | Set-ImperionThreadsReplyToBronze
    .EXAMPLE
        Get-ImperionThreadsReply -PostId '178414...'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('external_id')][string[]] $PostId,
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    begin {
        $cfg = Get-ImperionConfig
        if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
        $Token = Resolve-ImperionThreadsToken -Token $Token -FailClosed

        $map = [ordered]@{
            root_post_external_id   = '_imperionRootPostId'
            replied_to_external_id  = 'replied_to.id'
            threads_user_id         = 'owner.id'
            username                = 'username'
            text_content            = 'text'
            media_type              = 'media_type'
            permalink               = 'permalink'
            hide_status             = 'hide_status'
            created_time            = 'timestamp'
        }
        $fields = 'id,username,text,media_type,permalink,timestamp,hide_status,replied_to,owner'
    }
    process {
        foreach ($id in $PostId) {
            if (-not $id) { continue }
            $uri = '{0}/replies?fields={1}&limit=100' -f [uri]::EscapeDataString($id), $fields
            $replies = @(Invoke-ImperionThreadsRequest -Token $Token -Uri $uri -MaxPages $MaxPages)
            foreach ($reply in $replies) {
                $reply | Add-Member -NotePropertyName '_imperionRootPostId' -NotePropertyValue $id -Force
            }
            $replies | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'threads' -TenantId $TenantId -ExternalIdProperty 'id'
        }
    }
}
