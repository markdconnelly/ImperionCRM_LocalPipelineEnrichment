function Set-ImperionMetaPostToBronze {
    <#
    .SYNOPSIS
        Write flattened Facebook Page post rows into the facebook_posts bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), issue #126. Takes the flat rows produced by
        Get-ImperionMetaPagePost and upserts them (standard envelope, change-detected).
        Each row is projected to exactly the facebook_posts column set defined by
        front-end migration 0075 before the upsert, so a corrected collector field can
        never break the insert; anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Idempotent/resumable.
        Pass an open -Connection to share one across a batch. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionMetaPagePost (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to facebook_posts (front-end migration 0075).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionMetaPagePost -PageId $pageId | Set-ImperionMetaPostToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'facebook_posts'
    )

    begin {
        # Exact column set of facebook_posts (front-end migration 0075): flat columns
        # first, then the standard envelope.
        $tableColumns = @(
            'page_id', 'message', 'story', 'status_type', 'permalink_url',
            'from_id', 'from_name', 'created_time', 'updated_time',
            'is_published', 'comment_count', 'reaction_count', 'share_count',
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
