function Set-ImperionQboPurchaseToBronze {
    <#
    .SYNOPSIS
        Write flattened QBO purchase rows into the qbo_purchases bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionQboPurchase and upserts them (standard envelope,
        change-detected: unchanged content hashes are not rewritten). Each row is projected to
        exactly the qbo_purchases column set before the upsert, so a corrected collector field can
        never break the insert; anything extra survives in raw_payload. The backend Payroll
        Reconciliation (ImperionCRM_Backend#105) and expense-reimbursement reconciliation
        (front-end ADR-0083) read this bronze fact to set a timesheet **Paid** / a reimbursement
        **Reimbursed** (the payment-fact authority, front-end ADR-0082/ADR-0085).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue #105)
        — it owns the projection/gate/connection/upsert/log/tally; this declares table + column
        set. The metric log records counts only — never the payment amount or payee. Idempotent/
        resumable on external_id (the QBO Purchase Id). Pass an open -Connection to share one
        across a batch. Requires Initialize-ImperionContext.

        TARGET: bronze `qbo_purchases` (front-end-owned schema, ADR-0042). Front-end migration 0092
        is SHIPPED (markdconnelly/ImperionCRM#526; supersedes 0091/qbo_bill_payments — Simple Start
        has no Accounts Payable). The scheduled task remains GATED on the QBO app registration
        (logs + exits) until the `qbo-access-token`/`qbo-realm-id` secrets land.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionQboPurchase (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_purchases (front-end migration 0092).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboPurchase | Set-ImperionQboPurchaseToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_purchases'
    )

    begin {
        # Exact column set of qbo_purchases (front-end migration 0092): flat finance columns
        # first, then the standard envelope. Extra collector fields are dropped from the flat
        # projection (they remain queryable in raw_payload).
        $tableColumns = @(
            'txn_date', 'total_amount', 'payment_type', 'account_ref', 'account_name',
            'entity_id', 'entity_type', 'entity_name', 'doc_number', 'currency',
            'created_time', 'last_updated_time',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'qbo' -ColumnSet $tableColumns
    }
}
