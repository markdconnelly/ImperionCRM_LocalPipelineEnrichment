function Set-ImperionThreadsPostToBronze {
    <#
    .SYNOPSIS
        Write flattened Threads post rows into the threads_posts bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), LocalPipeline #356. Takes the flat rows produced by
        Get-ImperionThreadsPost and upserts them (standard envelope, change-detected). Each
        row is projected to exactly the threads_posts column set defined by front-end
        migration 0208 before the upsert, so a corrected collector field can never break the
        insert; anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost. Idempotent/resumable on
        (tenant_id, source, external_id). Pass an open -Connection to share one across a
        batch. Post text is PII-adjacent (our own public content) — never logged. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionThreadsPost (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to threads_posts (front-end migration 0208).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionThreadsPost | Set-ImperionThreadsPostToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet.')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'threads_posts'
    )

    begin {
        # Exact column set of threads_posts (front-end migration 0208): flat columns first,
        # then the standard envelope.
        $tableColumns = @(
            'threads_user_id', 'username', 'text_content', 'media_type',
            'permalink', 'shortcode', 'is_quote_post', 'reply_audience', 'created_time',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'threads' -ColumnSet $tableColumns
    }
}
