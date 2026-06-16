function Set-ImperionQboPaymentToBronze {
    <#
    .SYNOPSIS
        Write flattened QBO customer-payment rows into the qbo_payments bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject] rows from
        Get-ImperionQboPayment and upserts them (standard envelope, change-detected). Each row is
        projected to exactly the qbo_payments column set before the upsert; extras survive in
        raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). FAILS LOUDLY if `qbo_payments` is
        absent (schema is front-end-owned, ADR-0005/ADR-0042; front-end migration 0120). The metric
        log records COUNTS ONLY — never amounts or customer names (financial PII, CLAUDE.md §8).
        Idempotent on external_id (the QBO Payment Id). Distinct from `Set-ImperionQboPurchaseToBronze`
        (cash OUT). Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionQboPayment (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_payments (front-end migration 0120).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboPayment | Set-ImperionQboPaymentToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_payments'
    )

    begin {
        # Exact column set of qbo_payments (front-end migration 0120).
        $tableColumns = @(
            'txn_date', 'total_amount', 'unapplied_amount', 'customer_ref', 'customer_name',
            'deposit_account', 'payment_method', 'currency', 'created_time', 'last_updated_time',
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
