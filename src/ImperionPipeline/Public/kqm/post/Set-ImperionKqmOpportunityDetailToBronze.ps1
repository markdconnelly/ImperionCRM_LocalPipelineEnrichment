function Set-ImperionKqmOpportunityDetailToBronze {
    <#
    .SYNOPSIS
        Write the four KQM won-quote detail sets into their bronze tables (sections / lines /
        sales orders / sales-order lines).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the detail object produced by
        Get-ImperionKqmOpportunityDetail. Each set is upserted into its own front-end migration
        0083 table with that table's exact -ColumnSet, so a corrected collector field can never
        break an insert and anything extra survives in raw_payload. Idempotent/resumable: an
        unchanged content-hash skips the row (no churn on the daily full pull).

        Four thin Invoke-ImperionBronzePost calls over one shared connection (opened here when
        -Connection is omitted, so all four tables write in one short-lived-token session).
        Returns one tally per table. Requires Initialize-ImperionContext.
    .PARAMETER Detail
        The [pscustomobject] from Get-ImperionKqmOpportunityDetail (Sections / Lines /
        SalesOrders / SalesOrderLines). Null or all-empty → four zero tallies, no DB call.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .OUTPUTS
        [pscustomobject] of { sections; lines; salesOrders; salesOrderLines } upsert tallies.
    .EXAMPLE
        Get-ImperionKqmOpportunityDetail -WonQuoteId $won | Set-ImperionKqmOpportunityDetailToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Detail,
        $Connection
    )

    begin {
        # Exact column sets of the four kqm_* detail tables (front-end migration 0083): verified
        # flat columns first, then the standard envelope shared by all four.
        $envelope = @('tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash')
        $columns = @{
            kqm_opportunity_sections  = @('quote_id', 'type', 'line_number', 'is_multi_choice', 'is_selected', 'title') + $envelope
            kqm_opportunity_lines     = @('quote_section_id', 'line_number', 'product_id', 'product_number',
                'title', 'description', 'price', 'quantity', 'tax', 'tax_rate', 'discount_method',
                'discount_value', 'is_optional', 'is_selected', 'is_recurring', 'recurring_type',
                'recurring_duration', 'created_date', 'modified_date') + $envelope
            kqm_sales_orders          = @('quote_id', 'order_number', 'order_date', 'status', 'fulfillment_status',
                'entry_type', 'customer_id', 'created_date', 'modified_date') + $envelope
            kqm_sales_order_lines     = @('sales_order_id', 'product_id', 'line_number', 'cost', 'price', 'tax',
                'tax_rate', 'quantity', 'title', 'description', 'serial_numbers', 'is_recurring',
                'recurring_type', 'recurring_duration', 'created_date', 'modified_date') + $envelope
        }
        $details = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($d in $Detail) { if ($null -ne $d) { $details.Add($d) } }
    }
    end {
        # Accumulate each set across any piped detail objects (typically exactly one).
        $sets = @{
            kqm_opportunity_sections = [System.Collections.Generic.List[object]]::new()
            kqm_opportunity_lines    = [System.Collections.Generic.List[object]]::new()
            kqm_sales_orders         = [System.Collections.Generic.List[object]]::new()
            kqm_sales_order_lines    = [System.Collections.Generic.List[object]]::new()
        }
        foreach ($d in $details) {
            foreach ($r in @(Get-ImperionMember $d 'Sections')) { if ($r) { $sets.kqm_opportunity_sections.Add($r) } }
            foreach ($r in @(Get-ImperionMember $d 'Lines')) { if ($r) { $sets.kqm_opportunity_lines.Add($r) } }
            foreach ($r in @(Get-ImperionMember $d 'SalesOrders')) { if ($r) { $sets.kqm_sales_orders.Add($r) } }
            foreach ($r in @(Get-ImperionMember $d 'SalesOrderLines')) { if ($r) { $sets.kqm_sales_order_lines.Add($r) } }
        }

        # One short-lived-token connection shared across the four tables (ADR-0003).
        $ownConnection = $null
        if (-not $Connection) { $ownConnection = New-ImperionDbConnection; $Connection = $ownConnection }
        try {
            $write = {
                param([string] $table)
                Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
                    -Rows $sets[$table].ToArray() -Table $table -LogSource 'kqm' -ColumnSet $columns[$table]
            }
            [pscustomobject]@{
                sections        = & $write 'kqm_opportunity_sections'
                lines           = & $write 'kqm_opportunity_lines'
                salesOrders     = & $write 'kqm_sales_orders'
                salesOrderLines = & $write 'kqm_sales_order_lines'
            }
        }
        finally {
            if ($ownConnection) { $ownConnection.Dispose() }
        }
    }
}
