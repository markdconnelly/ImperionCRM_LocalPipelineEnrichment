function Set-ImperionQboBillPaymentToBronze {
    <#
    .SYNOPSIS
        Write flattened QBO bill-payment rows into the qbo_bill_payments bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionQboBillPayment and upserts them (standard envelope,
        change-detected: unchanged content hashes are not rewritten). Each row is projected to
        exactly the qbo_bill_payments column set before the upsert, so a corrected collector
        field can never break the insert; anything extra survives in raw_payload. The backend
        Payroll Reconciliation (ImperionCRM_Backend#105) reads this bronze fact to set a
        timesheet **Paid** (the payment-fact authority, ADR-0082).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the projection/gate/connection/upsert/log/tally; this declares table +
        column set. The metric log records counts only — never the payment amount or vendor.
        Idempotent/resumable on external_id (the QBO BillPayment Id). Pass an open -Connection
        to share one across a batch. Requires Initialize-ImperionContext.

        TARGET: bronze `qbo_bill_payments` (front-end-owned schema, ADR-0042). The table is
        PROPOSED (docs/integrations/quickbooks-online.md + this repo's QBO ADR) and does not
        exist yet — the scheduled task is GATED/deploy-ahead (logs + exits) until the front-end
        migration and the QBO app registration land.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionQboBillPayment (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_bill_payments (proposed front-end migration).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboBillPayment | Set-ImperionQboBillPaymentToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_bill_payments'
    )

    begin {
        # Exact column set of qbo_bill_payments (proposed front-end migration): flat finance
        # columns first, then the standard envelope. Extra collector fields are dropped from
        # the flat projection (they remain queryable in raw_payload).
        $tableColumns = @(
            'txn_date', 'total_amount', 'vendor_id', 'vendor_name', 'pay_type', 'doc_number',
            'currency', 'created_time', 'last_updated_time',
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
