function Set-ImperionQboBillToBronze {
    <#
    .SYNOPSIS
        Write flattened QBO vendor-bill (A/P) rows into the qbo_bills bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject] rows from
        Get-ImperionQboBill and upserts them (standard envelope, change-detected). Each row is
        projected to exactly the qbo_bills column set before the upsert; extras survive in
        raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). FAILS LOUDLY if `qbo_bills` is
        absent (schema is front-end-owned, ADR-0005/ADR-0042; front-end migration 0120 models it for
        completeness). On a Simple Start company `Get-ImperionQboBill` yields NO rows (A/P is not
        available — graceful degrade), so this writer simply returns the zero tally and never touches
        the database; the table stays dormant (ADR-0020 §1 open item / CONFIRM-BEFORE-LIVE). The
        metric log records COUNTS ONLY — never amounts or vendor names (financial PII, CLAUDE.md §8).
        Idempotent on external_id (the QBO Bill Id). Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionQboBill (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_bills (front-end migration 0120).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboBill | Set-ImperionQboBillToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_bills'
    )

    begin {
        # Exact column set of qbo_bills (front-end migration 0120).
        $tableColumns = @(
            'doc_number', 'txn_date', 'due_date', 'total_amount', 'balance',
            'vendor_ref', 'vendor_name', 'ap_account_ref', 'currency', 'created_time', 'last_updated_time',
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
