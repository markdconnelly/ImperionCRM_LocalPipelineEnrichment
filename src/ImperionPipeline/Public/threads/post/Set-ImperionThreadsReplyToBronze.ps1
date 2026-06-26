function Set-ImperionThreadsReplyToBronze {
    <#
    .SYNOPSIS
        Write flattened Threads reply rows into the threads_replies bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), LocalPipeline #356. Takes the flat rows produced by
        Get-ImperionThreadsReply and upserts them (standard envelope, change-detected),
        projected to exactly the threads_replies column set defined by front-end migration
        0208 before the upsert; anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost. Idempotent/resumable on
        (tenant_id, source, external_id). Pass an open -Connection to share one across a
        batch. Reply text is PII-adjacent — never logged. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionThreadsReply (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to threads_replies (front-end migration 0208).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionThreadsPost | Get-ImperionThreadsReply | Set-ImperionThreadsReplyToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet.')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'threads_replies'
    )

    begin {
        # Exact column set of threads_replies (front-end migration 0208).
        $tableColumns = @(
            'root_post_external_id', 'replied_to_external_id', 'threads_user_id', 'username',
            'text_content', 'media_type', 'permalink', 'hide_status', 'created_time',
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
