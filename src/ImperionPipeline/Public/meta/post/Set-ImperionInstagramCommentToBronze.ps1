function Set-ImperionInstagramCommentToBronze {
    <#
    .SYNOPSIS
        Write flattened Instagram comment rows into the instagram_comments bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), issue #126. Takes the flat rows produced by
        Get-ImperionInstagramComment and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the instagram_comments column
        set defined by front-end migration 0075 before the upsert; anything extra
        survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Idempotent/resumable.
        Pass an open -Connection to share one across a batch. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionInstagramComment (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to instagram_comments (front-end migration 0075).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionInstagramMedia -PageId $pageId | Get-ImperionInstagramComment | Set-ImperionInstagramCommentToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'instagram_comments'
    )

    begin {
        # Exact column set of instagram_comments (front-end migration 0075).
        $tableColumns = @(
            'media_external_id', 'parent_comment_id', 'comment_text',
            'username', 'from_id', 'created_time', 'like_count',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'meta' -ColumnSet $tableColumns
    }
}
