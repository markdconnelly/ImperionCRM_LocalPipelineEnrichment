function Get-ImperionMetaPostComment {
    <#
    .SYNOPSIS
        Collect comments on Facebook Page posts and flatten them to facebook_comments bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source, issue #126. Takes post
        ids from the pipeline (the rows Get-ImperionMetaPagePost emits bind by their
        external_id property) or an explicit -PostId array, pages /{post-id}/comments
        per post, and flattens to the facebook_comments column set (front-end migration
        0075). Commenters are TIMELINE-ONLY in silver — they become interactions, never
        leads (the 0075 contract). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat: fields follow Meta's published comment reference;
        anything the token cannot read lands NULL in the flat column and survives in
        raw_payload. Verify against a live first run.
    .PARAMETER PostId
        Facebook post ids to collect comments for. Accepts pipeline input — including
        the flattened post rows themselves (binds external_id by property name).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user token override. Defaults to the SecretStore resolution (ADR-0013).
    .PARAMETER MaxPages
        Paging cap per post forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionMetaPagePost -PageId $pageId | Get-ImperionMetaPostComment
    .EXAMPLE
        Get-ImperionMetaPostComment -PostId '123_456', '123_789'
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
        $Token = Resolve-ImperionMetaToken -Token $Token

        $map = [ordered]@{
            post_external_id  = '_imperionPostId'
            parent_comment_id = 'parent.id'
            message           = 'message'
            from_id           = 'from.id'
            from_name         = 'from.name'
            created_time      = 'created_time'
            like_count        = 'like_count'
            comment_count     = 'comment_count'
        }
        $fields = 'message,from,created_time,like_count,comment_count,parent'
    }
    process {
        foreach ($id in $PostId) {
            if (-not $id) { continue }
            $uri = '{0}/comments?fields={1}&limit=100' -f [uri]::EscapeDataString($id), $fields
            $comments = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri -MaxPages $MaxPages)
            foreach ($comment in $comments) {
                $comment | Add-Member -NotePropertyName '_imperionPostId' -NotePropertyValue $id -Force
            }
            $comments | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'facebook' -TenantId $TenantId -ExternalIdProperty 'id'
        }
    }
}
