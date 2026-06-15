function Set-ImperionQboExpenseAccountToBronze {
    <#
    .SYNOPSIS
        Write flattened QBO expense-account rows into the qbo_expense_account bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject] rows
        produced by Get-ImperionQboExpenseAccount and upserts them (standard envelope,
        change-detected: unchanged content hashes are not rewritten). Each row is projected to
        exactly the qbo_expense_account column set before the upsert, so a corrected collector
        field can never break the insert; anything extra survives in raw_payload. A front-end
        admin maps each bronze account to a clean website `expense_category` (front-end #489);
        the app never writes QuickBooks (ADR-0083).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue #105) —
        it owns the projection/gate/connection/upsert/log/tally; this declares table + column set.
        Idempotent/resumable on external_id (the QBO Account Id). Pass an open -Connection to share
        one across a batch. Requires Initialize-ImperionContext.

        TARGET: bronze `qbo_expense_account` (front-end-owned schema, ADR-0042). The table is
        PROPOSED (docs/integrations/quickbooks-online.md + ADR-0014) and does not exist yet — the
        scheduled task is GATED/deploy-ahead (logs + exits) until the front-end migration and the
        QBO chart-of-accounts read scope land.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionQboExpenseAccount (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_expense_account (proposed front-end migration).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboExpenseAccount | Set-ImperionQboExpenseAccountToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_expense_account'
    )

    begin {
        # Exact column set of qbo_expense_account (proposed front-end migration): flat
        # chart-of-accounts columns first, then the standard envelope. Extra collector fields are
        # dropped from the flat projection (they remain queryable in raw_payload).
        $tableColumns = @(
            'name', 'fully_qualified_name', 'account_type', 'account_sub_type', 'classification',
            'active', 'created_time', 'last_updated_time',
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
