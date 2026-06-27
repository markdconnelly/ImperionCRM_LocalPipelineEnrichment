function ConvertTo-ImperionMetaMentionRow {
    <#
    .SYNOPSIS
        Flatten one Meta tagged-post / tagged-media item into a meta_mentions bronze row (private).
    .DESCRIPTION
        Private helper for Get-ImperionMetaMention. The meta_mentions bronze table (front-end
        #1365) does NOT use the standard bronze envelope (no tenant_id/source/content_hash/
        collected_at) — it is keyed on UNIQUE (platform, mention_id) with a `raw` jsonb payload
        and a DB-default id/ingested_at. So this builds the exact column set by hand rather than
        via ConvertTo-ImperionFlatObject (which would add the standard envelope columns that this
        table lacks). Flat cells are coerced to stable bronze text (Format-ImperionScalar); the
        full source object survives in `raw`. StrictMode-safe — a missing field lands NULL.
    .PARAMETER Item
        The raw source object (a /tagged post or a /tags media item).
    .PARAMETER Platform
        'facebook' | 'instagram'.
    .PARAMETER MentionKind
        tagged_post | tagged_media | comment_mention.
    .PARAMETER PermalinkPath
        Dotted path to the permalink on the source object.
    .PARAMETER MessagePath
        Dotted path to the message/caption body.
    .PARAMETER AuthorIdPath
        Dotted path to the mention author's id.
    .PARAMETER AuthorNamePath
        Dotted path to the author's display name.
    .PARAMETER AuthorUsernamePath
        Dotted path to the author's username/handle.
    .PARAMETER CreatedTimePath
        Dotted path to the created timestamp.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)][ValidateSet('facebook', 'instagram')][string] $Platform,
        [Parameter(Mandatory)][string] $MentionKind,
        [Parameter(Mandatory)][string] $PermalinkPath,
        [Parameter(Mandatory)][string] $MessagePath,
        [Parameter(Mandatory)][string] $AuthorIdPath,
        [Parameter(Mandatory)][string] $AuthorNamePath,
        [Parameter(Mandatory)][string] $AuthorUsernamePath,
        [Parameter(Mandatory)][string] $CreatedTimePath
    )

    # Exact meta_mentions column set (front-end #1365). id / ingested_at have DB defaults — omitted.
    [pscustomobject][ordered]@{
        platform         = $Platform
        mention_id       = [string](Get-ImperionPropertyPath -InputObject $Item -Path 'id')
        mention_kind     = $MentionKind
        permalink        = Format-ImperionScalar -Value (Get-ImperionPropertyPath -InputObject $Item -Path $PermalinkPath)
        message          = Format-ImperionScalar -Value (Get-ImperionPropertyPath -InputObject $Item -Path $MessagePath)
        author_id        = Format-ImperionScalar -Value (Get-ImperionPropertyPath -InputObject $Item -Path $AuthorIdPath)
        author_username  = Format-ImperionScalar -Value (Get-ImperionPropertyPath -InputObject $Item -Path $AuthorUsernamePath)
        author_name      = Format-ImperionScalar -Value (Get-ImperionPropertyPath -InputObject $Item -Path $AuthorNamePath)
        created_time     = Format-ImperionScalar -Value (Get-ImperionPropertyPath -InputObject $Item -Path $CreatedTimePath)
        raw              = ($Item | ConvertTo-Json -Compress -Depth 20)
    }
}
