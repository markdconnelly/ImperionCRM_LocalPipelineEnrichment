function Set-ImperionMetaMessageToBronze {
    <#
    .SYNOPSIS
        Write flattened page-inbox (Messenger) message rows into the facebook_messages bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), issue #126. Takes the flat per-message rows
        produced by Get-ImperionMetaConversation and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the facebook_messages column
        set defined by front-end migration 0075 before the upsert; anything extra
        survives in raw_payload. DM senders become leads downstream
        (Invoke-ImperionMetaMerge) — these rows carry PII; never log their contents.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Idempotent/resumable.
        Pass an open -Connection to share one across a batch. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionMetaConversation (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to facebook_messages (front-end migration 0075).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionMetaConversation -PageId $pageId | Set-ImperionMetaMessageToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'facebook_messages'
    )

    begin {
        # Exact column set of facebook_messages (front-end migration 0075).
        $tableColumns = @(
            'conversation_id', 'page_id', 'message',
            'from_id', 'from_name', 'to_id', 'to_name', 'created_time',
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
