function Set-ImperionKqmProposalToBronze {
    <#
    .SYNOPSIS
        Write flattened KQM quote rows into the kqm_proposals bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), issue #98. Takes the flat rows produced by
        Get-ImperionKqmProposal and upserts them (standard envelope, change-detected).
        Each row is projected to exactly the kqm_proposals column set defined by
        front-end migration 0038 (name, status, total, account_ref, created_at,
        updated_at) before the upsert, so a corrected collector field can never break
        the insert; anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Idempotent/resumable.
        Pass an open -Connection to share one across a batch. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionKqmProposal (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to kqm_proposals (front-end migration 0038).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionKqmProposal | Set-ImperionKqmProposalToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'kqm_proposals'
    )

    begin {
        # Exact column set of kqm_proposals (front-end migration 0038): flat columns first,
        # then the standard envelope.
        $tableColumns = @(
            'name', 'status', 'total', 'account_ref', 'created_at', 'updated_at',
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
