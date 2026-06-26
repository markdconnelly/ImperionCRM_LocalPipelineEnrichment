function Set-ImperionMetaLeadToBronze {
    <#
    .SYNOPSIS
        Write flattened Meta Lead Ad submitted-lead rows into the meta_lead_ads bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), LP #362. Takes the flat per-lead rows produced by
        Get-ImperionMetaLead and upserts them (standard envelope, change-detected). Each row
        is projected to exactly the meta_lead_ads column set defined by front-end migration
        0207 before the upsert; anything extra survives in raw_payload. These rows carry
        PII-adjacent field_data — never log their contents (ADR-0086). Submitters become
        leads downstream (Invoke-ImperionMetaLeadAdsMerge).

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Idempotent/resumable. Pass
        an open -Connection to share one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionMetaLead (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to meta_lead_ads (front-end migration 0207).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionMetaLead -FormId $formId | Set-ImperionMetaLeadToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'meta_lead_ads'
    )

    begin {
        # Exact column set of meta_lead_ads (front-end migration 0207).
        $tableColumns = @(
            'form_id', 'page_id', 'ad_id', 'ad_name',
            'adset_id', 'campaign_id', 'campaign_name', 'platform',
            'is_organic', 'field_data', 'full_name', 'email', 'phone_number', 'created_time',
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
