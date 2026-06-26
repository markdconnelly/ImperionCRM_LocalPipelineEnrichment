function Set-ImperionInstagramMessageToBronze {
    <#
    .SYNOPSIS
        Write flattened Instagram Direct Message rows into the instagram_messages bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), LocalPipeline #361. Takes the flat per-message
        rows produced by Get-ImperionInstagramMessage and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the instagram_messages column
        set defined by front-end migration 0207 before the upsert; anything extra survives
        in raw_payload. DM senders become leads downstream (Invoke-ImperionMetaMerge) —
        these rows carry PII; never log their contents.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Idempotent/resumable.
        Pass an open -Connection to share one across a batch. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionInstagramMessage (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to instagram_messages (front-end migration 0207).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionInstagramMessage -PageId $pageId | Set-ImperionInstagramMessageToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'instagram_messages'
    )

    begin {
        # Exact column set of instagram_messages (front-end migration 0207).
        $tableColumns = @(
            'conversation_id', 'ig_user_id', 'message',
            'from_id', 'from_username', 'to_id', 'to_username', 'created_time',
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
