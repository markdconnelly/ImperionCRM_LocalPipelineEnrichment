function Set-ImperionQboAccountToBronze {
    <#
    .SYNOPSIS
        Write flattened QBO full chart-of-accounts rows into the qbo_accounts bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject] rows from
        Get-ImperionQboAccount (the FULL chart of accounts) and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the qbo_accounts column set before the
        upsert; extras survive in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). FAILS LOUDLY if `qbo_accounts` is
        absent (schema is front-end-owned, ADR-0005/ADR-0042; front-end migration 0120). Reference
        data (account names, not PII); the metric log records counts only. Idempotent on external_id
        (the QBO Account Id). Distinct from `Set-ImperionQboExpenseAccountToBronze` (the expense-only
        slice → `qbo_expense_account`); whether that becomes a view over this full table is a
        front-end migration-author call (ADR-0020 open item). Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionQboAccount (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_accounts (front-end migration 0120).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboAccount | Set-ImperionQboAccountToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_accounts'
    )

    begin {
        # Exact column set of qbo_accounts (front-end migration 0120).
        $tableColumns = @(
            'name', 'fully_qualified_name', 'account_type', 'account_sub_type', 'classification',
            'current_balance', 'active', 'currency', 'created_time', 'last_updated_time',
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
