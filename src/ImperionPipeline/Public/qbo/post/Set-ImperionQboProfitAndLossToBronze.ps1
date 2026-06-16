function Set-ImperionQboProfitAndLossToBronze {
    <#
    .SYNOPSIS
        Write a flattened QBO Profit & Loss snapshot row into the qbo_profit_and_loss bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject] snapshot
        row(s) from Get-ImperionQboProfitAndLoss and upserts them (standard envelope, change-
        detected). Each row is projected to exactly the qbo_profit_and_loss column set before the
        upsert; the full report survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). FAILS LOUDLY if
        `qbo_profit_and_loss` is absent (schema is front-end-owned, ADR-0005/ADR-0042; front-end
        migration 0120). external_id = the report `period` (ADR-0011 immutable snapshot idiom), so the
        standard `(tenant_id, source, external_id)` upsert + content-hash skip make a re-pull of the
        same period converge — an unchanged snapshot is never rewritten. The metric log records counts
        only — never the report totals. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze snapshot row(s) from Get-ImperionQboProfitAndLoss (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_profit_and_loss (front-end migration 0120).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboProfitAndLoss | Set-ImperionQboProfitAndLossToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_profit_and_loss'
    )

    begin {
        # Exact column set of qbo_profit_and_loss (front-end migration 0120). The snapshot row's
        # external_id is the period; headline totals are surfaced, the full report is in raw_payload.
        $tableColumns = @(
            'period', 'start_date', 'end_date', 'report_period', 'currency',
            'total_income', 'total_expenses', 'net_income', 'generated_time',
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
