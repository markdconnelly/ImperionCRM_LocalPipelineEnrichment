function Set-ImperionEasyDmarcDomainToBronze {
    <#
    .SYNOPSIS
        Write flattened EasyDMARC domain-posture rows into the easydmarc_domains bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for EasyDMARC (issue #122). Takes the flat rows
        produced by Get-ImperionEasyDmarcDomain and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the PROPOSED easydmarc_domains
        column set before the upsert, so a corrected collector field can never break the
        insert; anything extra survives in raw_payload.

        SCHEMA OWNERSHIP: easydmarc_domains is a NEW bronze table. Schema lives in the
        front-end repo (system CLAUDE.md §1) — this PR does NOT add a migration; it is
        authored against the bronze migration proposed in ImperionCRM issue #581.
        Until that migration is applied, the scheduled task is gated and this writer is
        dormant.

        Thin adapter over Invoke-ImperionBronzePost (the shared post-writer scaffold, issue
        #105). Idempotent/resumable. Pass an open -Connection to share one across a batch;
        otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionEasyDmarcDomain (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to easydmarc_domains (proposed front-end migration).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionEasyDmarcDomain | Set-ImperionEasyDmarcDomainToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'easydmarc_domains'
    )

    begin {
        # Exact column set of the PROPOSED easydmarc_domains table (front-end issue #581):
        # the flat posture columns first, then the standard envelope.
        $tableColumns = @(
            'domain', 'organization_ref', 'setup_status', 'dmarc_policy', 'dmarc_status',
            'spf_status', 'dkim_status', 'bimi_status',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'easydmarc' -ColumnSet $tableColumns
    }
}
