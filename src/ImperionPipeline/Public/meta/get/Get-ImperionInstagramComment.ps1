function Get-ImperionInstagramComment {
    <#
    .SYNOPSIS
        Collect comments on Instagram media and flatten them to instagram_comments bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source, issue #126. Takes media
        ids from the pipeline (the rows Get-ImperionInstagramMedia emits bind by their
        external_id property) or an explicit -MediaId array, pages /{media-id}/comments
        per media item, and flattens to the instagram_comments column set (front-end
        migration 0075: comment_text <- text, created_time <- timestamp). Commenters are
        TIMELINE-ONLY in silver — interactions, never leads (the 0075 contract).
        Returns rows; does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat: fields follow Meta's published IG-comment reference;
        `from` in particular is permission-gated (instagram_manage_comments tier) and is
        read tolerantly — from_id lands NULL when absent and the username field still
        identifies the commenter. Full payload survives in raw_payload. Verify against a
        live first run.
    .PARAMETER MediaId
        Instagram media ids to collect comments for. Accepts pipeline input — including
        the flattened media rows themselves (binds external_id by property name).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user token override. Defaults to the SecretStore resolution (ADR-0013).
    .PARAMETER MaxPages
        Paging cap per media item forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionInstagramMedia -PageId $pageId | Get-ImperionInstagramComment
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('external_id')][string[]] $MediaId,
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    begin {
        $cfg = Get-ImperionConfig
        if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
        $Token = Resolve-ImperionMetaToken -Token $Token

        $map = [ordered]@{
            media_external_id = '_imperionMediaId'
            parent_comment_id = 'parent_id'
            comment_text      = 'text'
            username          = 'username'
            from_id           = 'from.id'
            created_time      = 'timestamp'
            like_count        = 'like_count'
        }
        $fields = 'text,username,from,timestamp,like_count,parent_id'
    }
    process {
        foreach ($id in $MediaId) {
            if (-not $id) { continue }
            $uri = '{0}/comments?fields={1}&limit=100' -f [uri]::EscapeDataString($id), $fields
            $comments = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri -MaxPages $MaxPages)
            foreach ($comment in $comments) {
                $comment | Add-Member -NotePropertyName '_imperionMediaId' -NotePropertyValue $id -Force
            }
            $comments | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'instagram' -TenantId $TenantId -ExternalIdProperty 'id'
        }
    }
}
