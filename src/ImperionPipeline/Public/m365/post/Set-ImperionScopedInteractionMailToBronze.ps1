function Set-ImperionScopedInteractionMailToBronze {
    <#
    .SYNOPSIS
        Write flattened scoped-mail rows into the m365_email bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the scoped interaction capture (issue #199, ADR-0022).
        Takes the flat, fully-enveloped [PSCustomObject] rows from Get-ImperionScopedInteractionMail
        (already scoped to allowlisted-principal ↔ client mail) and upserts them (standard lossless
        envelope, change-detected: unchanged content hashes are not rewritten). Each row is projected
        to exactly the m365_email column set before the upsert, so a corrected collector field can
        never break the insert; extras survive in raw_payload.

        Thin adapter over the shared Invoke-ImperionBronzePost scaffold (issue #105) — it owns the
        projection/gate/connection/upsert/log/tally; this declares table + column set. FAILS LOUDLY
        if `m365_email` is absent (the scaffold never creates tables — schema is front-end-owned,
        ADR-0005; front-end migration 0120 `bronze_batch_b`, already prod-applied). The metric log
        records COUNTS ONLY — never subjects, addresses, or message content (PII, CLAUDE.md §8).
        Idempotent/resumable on external_id (the Graph message id). Pass an open -Connection to share
        one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionScopedInteractionMail (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to m365_email (front-end migration 0120).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionScopedInteractionMail | Set-ImperionScopedInteractionMailToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'm365_email'
    )

    begin {
        # Exact column set of m365_email (front-end migration 0120): flat message columns first,
        # then the standard envelope. Extra collector fields are dropped from the flat projection
        # (they remain queryable in raw_payload).
        $tableColumns = @(
            'message_id', 'conversation_id', 'subject', 'preview', 'from_address', 'to_recipients',
            'direction', 'sent_at', 'has_attachments', 'mailbox_owner',
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
