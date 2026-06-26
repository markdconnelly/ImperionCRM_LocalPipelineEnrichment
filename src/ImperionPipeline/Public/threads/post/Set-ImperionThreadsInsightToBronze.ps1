function Set-ImperionThreadsInsightToBronze {
    <#
    .SYNOPSIS
        Write flattened Threads insight snapshot rows into the threads_insights bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), LocalPipeline #356. Takes the flat rows produced by
        Get-ImperionThreadsInsight and upserts them (standard envelope, change-detected; the
        loader-built external_id "<entity_kind>:<entity_id>:<metric>:<period>:<end_time>"
        makes each value point naturally idempotent). Each row is projected to exactly the
        threads_insights column set defined by front-end migration 0208 before the upsert;
        anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost. Idempotent/resumable. Pass an open
        -Connection to share one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionThreadsInsight (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to threads_insights (front-end migration 0208).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionThreadsInsight -ThreadsUserId $id | Set-ImperionThreadsInsightToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet.')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'threads_insights'
    )

    begin {
        # Exact column set of threads_insights (front-end migration 0208).
        $tableColumns = @(
            'entity_kind', 'entity_external_id', 'metric', 'period', 'end_time', 'value',
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
