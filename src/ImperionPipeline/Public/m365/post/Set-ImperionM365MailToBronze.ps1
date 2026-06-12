function Set-ImperionM365MailToBronze {
    <#
    .SYNOPSIS
        Write flattened cross-org mail rows into the m365_mail_messages bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the m365 communications path (issue #100;
        front-end migration 0065 / ImperionCRM#182). Takes the flat, fully-enveloped
        [PSCustomObject] rows produced by Get-ImperionM365Mail (source 'm365_email',
        cross-org filtered) and upserts them (standard envelope, change-detected). Each
        row is projected to exactly the migration-0065 column set; extras survive in
        raw_payload. The cloud Pipeline merge + backend interaction-timeline ingestion
        read this table (their SELECT grants ship in 0065).

        NOTE: migration 0065 is merged but not yet applied to prod (orchestrator batches
        the apply) — until then the upsert fails loudly and the task's catch gates it.

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionM365Mail (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to m365_mail_messages (front-end migration 0065).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionM365Mail -Mailbox 'ada@imperionllc.com' -ClientDomain 'acme.com' | Set-ImperionM365MailToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'm365_mail_messages'
    )

    begin {
        # Exact column set of m365_mail_messages (front-end migration 0065).
        $tableColumns = @(
            'mailbox', 'subject', 'from_address', 'from_name', 'to_addresses', 'cc_addresses',
            'received_date_time', 'sent_date_time', 'conversation_id', 'has_attachments',
            'importance', 'is_read', 'web_link',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'm365' -ColumnSet $tableColumns
    }
}
