function Set-ImperionQboEstimateToBronze {
    <#
    .SYNOPSIS
        Write flattened QBO estimate rows into the qbo_estimates bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject] rows from
        Get-ImperionQboEstimate and upserts them (standard envelope, change-detected). Each row is
        projected to exactly the qbo_estimates column set before the upsert; extras survive in
        raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). FAILS LOUDLY if `qbo_estimates` is
        absent (schema is front-end-owned, ADR-0005/ADR-0042; front-end migration 0120). The metric
        log records COUNTS ONLY — never amounts or customer names (financial PII, CLAUDE.md §8).
        Idempotent on external_id (the QBO Estimate Id). Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionQboEstimate (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to qbo_estimates (front-end migration 0120).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionQboEstimate | Set-ImperionQboEstimateToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'qbo_estimates'
    )

    begin {
        # Exact column set of qbo_estimates (front-end migration 0120).
        $tableColumns = @(
            'doc_number', 'txn_date', 'expiration_date', 'txn_status', 'total_amount',
            'customer_ref', 'customer_name', 'currency', 'created_time', 'last_updated_time',
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
