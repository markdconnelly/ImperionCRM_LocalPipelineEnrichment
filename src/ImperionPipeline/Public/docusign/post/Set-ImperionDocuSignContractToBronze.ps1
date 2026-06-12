function Set-ImperionDocuSignContractToBronze {
    <#
    .SYNOPSIS
        Write flattened DocuSign envelope rows into the docusign_contracts bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionDocuSignEnvelope and upserts them (standard envelope,
        change-detected: unchanged content hashes are not rewritten). Each row's flat
        columns are projected to exactly the docusign_contracts column set defined by
        front-end migration 0038 (subject, status, account_ref, sent_at, completed_at)
        before the upsert, so a future collector field can never break the insert;
        anything extra survives in raw_payload. The cloud Pipeline's
        mergeDocusignContractSources sweeps this table into silver `contract`
        (front-end ADR-0044).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold
        (issue #105) — it owns the projection/gate/connection/upsert/log/tally; this
        declares table + column set.
        Idempotent/resumable. Pass an open -Connection to share one across a batch;
        otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionDocuSignEnvelope (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to docusign_contracts (front-end migration 0038).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionDocuSignEnvelope | Set-ImperionDocuSignContractToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'docusign_contracts'
    )

    begin {
        # Exact column set of docusign_contracts (front-end migration 0038): flat columns
        # first, then the standard envelope. Anything else the collector emitted is dropped
        # from the flat projection (it remains queryable in raw_payload).
        $tableColumns = @(
            'subject', 'status', 'account_ref', 'sent_at', 'completed_at',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'docusign' -ColumnSet $tableColumns
    }
}
