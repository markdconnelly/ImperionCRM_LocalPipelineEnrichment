function Set-ImperionKqmOpportunityToBronze {
    <#
    .SYNOPSIS
        Write flattened KQM quote-header rows into the kqm_opportunities bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat rows produced by
        Get-ImperionKqmOpportunity and upserts them (standard envelope, change-detected).
        Each row is projected to exactly the kqm_opportunities column set defined by
        front-end migration 0083 (ADR-0080/0039) before the upsert, so a corrected
        collector field can never break the insert; anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost. Idempotent/resumable. Pass an open
        -Connection to share one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionKqmOpportunity (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to kqm_opportunities (front-end migration 0083).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionKqmOpportunity | Set-ImperionKqmOpportunityToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'kqm_opportunities'
    )

    begin {
        # Exact column set of kqm_opportunities (front-end migration 0083): verified header
        # flat columns first, then the standard envelope.
        $tableColumns = @(
            'quote_number', 'code', 'title', 'status', 'sales_order_id', 'customer_id',
            'autotask_opportunity_id', 'autotask_organization_id', 'autotask_quote_id',
            'contact_name', 'contact_email', 'owner_employee_id',
            'created_date', 'modified_date', 'expiry_date',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'kqm' -ColumnSet $tableColumns
    }
}
