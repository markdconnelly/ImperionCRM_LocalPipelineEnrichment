function Set-ImperionMetaLeadFormToBronze {
    <#
    .SYNOPSIS
        Write flattened Meta Lead Ad form rows into the meta_lead_ad_forms bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), LP #362. Takes the flat per-form rows produced by
        Get-ImperionMetaLeadForm and upserts them (standard envelope, change-detected). Each
        row is projected to exactly the meta_lead_ad_forms column set defined by front-end
        migration 0207 before the upsert; anything extra survives in raw_payload. Form
        metadata only — no submitted PII.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Idempotent/resumable. Pass
        an open -Connection to share one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionMetaLeadForm (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to meta_lead_ad_forms (front-end migration 0207).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionMetaLeadForm -PageId $pageId | Set-ImperionMetaLeadFormToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'meta_lead_ad_forms'
    )

    begin {
        # Exact column set of meta_lead_ad_forms (front-end migration 0207).
        $tableColumns = @(
            'page_id', 'form_name', 'status', 'locale',
            'questions', 'context_card', 'follow_up_action_url', 'leads_count', 'created_time',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'meta_lead_ad' -ColumnSet $tableColumns
    }
}
