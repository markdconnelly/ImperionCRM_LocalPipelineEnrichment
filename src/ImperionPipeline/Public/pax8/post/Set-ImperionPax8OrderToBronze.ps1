function Set-ImperionPax8OrderToBronze {
    <#
    .SYNOPSIS
        Write flattened Pax8 order rows into the pax8_orders bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) — a thin adapter over Invoke-ImperionBronzePost (issue
        #105). Takes the flat, fully-enveloped rows from Get-ImperionPax8Order and upserts them
        (standard envelope, change-detected) projected to exactly the pax8_orders column set
        (front-end migration 0161); extras survive in raw_payload. NEVER creates the table — fails
        loudly at the upsert if it is absent (ADR-0005). Idempotent/resumable. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionPax8Order (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to pax8_orders.
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionPax8Order | Set-ImperionPax8OrderToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'pax8_orders'
    )

    begin {
        $tableColumns = @(
            'pax8_order_id', 'company_id', 'status', 'ordered_at', 'total',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'pax8' -ColumnSet $tableColumns
    }
}
