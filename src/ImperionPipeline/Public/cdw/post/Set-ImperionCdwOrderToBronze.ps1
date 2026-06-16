function Set-ImperionCdwOrderToBronze {
    <#
    .SYNOPSIS
        Write flattened CDW order rows into the cdw_orders bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject] rows from
        Get-ImperionCdwOrder and upserts them (standard lossless envelope, change-detected: unchanged
        content hashes are not rewritten). Each row is projected to exactly the cdw_orders column set
        before the upsert, so a corrected collector field can never break the insert; extras survive
        in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue #105) — it
        owns the projection/gate/connection/upsert/log/tally; this declares table + column set. FAILS
        LOUDLY if `cdw_orders` is absent (the scaffold never creates tables — schema is front-end-
        owned, ADR-0005/ADR-0042; front-end migration 0120). The metric log records COUNTS ONLY —
        never order totals or account refs (procurement detail, CLAUDE.md §8). Idempotent/resumable on
        external_id (the CDW order number). Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionCdwOrder (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to cdw_orders (front-end migration 0120).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionCdwOrder | Set-ImperionCdwOrderToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'cdw_orders'
    )

    begin {
        # Exact column set of cdw_orders (front-end migration 0120): flat logistics columns first,
        # then the standard envelope. Extra collector fields are dropped from the flat projection
        # (they remain queryable in raw_payload).
        $tableColumns = @(
            'order_id', 'po_number', 'order_date', 'order_status', 'order_total', 'currency',
            'account_ref', 'tracking_number', 'carrier', 'ship_status', 'estimated_delivery',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'cdw' -ColumnSet $tableColumns
    }
}
