function Set-ImperionMyItProcessRecommendationToBronze {
    <#
    .SYNOPSIS
        Write flattened myITprocess recommendation rows into the myitprocess_recommendations table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for myITprocess (issue #195, ADR-0018). Takes the flat
        rows produced by Get-ImperionMyItProcessRecommendation and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the myitprocess_recommendations column
        set before the upsert, so a corrected collector field can never break the insert; anything
        extra survives in raw_payload.

        SCHEMA OWNERSHIP: myitprocess_recommendations is owned by the front-end repo (system
        CLAUDE.md §1) — this PR does NOT add a migration. Front-end migration 0119 (front-end #674)
        is SHIPPED + prod-applied, so this writer is unblocked. NEVER creates the table; fails
        loudly if absent (ADR-0005). DOWNSTREAM CONSUMER: account-advisory rollups feed account
        health / QBR narrative (a possible new silver concept, a front-end call per ADR-0018) —
        NOT implemented here.

        Thin adapter over Invoke-ImperionBronzePost (the shared post-writer scaffold, issue #105).
        Idempotent/resumable on external_id (the recommendation id). Pass an open -Connection to
        share one across a batch; otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionMyItProcessRecommendation (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to myitprocess_recommendations (front-end migration 0119).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionMyItProcessRecommendation | Set-ImperionMyItProcessRecommendationToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'myitprocess_recommendations'
    )

    begin {
        # Exact column set of myitprocess_recommendations (front-end migration 0119): flat
        # advisory columns first, then the standard envelope.
        $tableColumns = @(
            'account_ref', 'assessment_name', 'recommendation_title', 'category', 'priority',
            'status', 'target_date',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'myitprocess' -ColumnSet $tableColumns
    }
}
