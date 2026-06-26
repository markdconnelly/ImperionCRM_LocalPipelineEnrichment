function Set-ImperionCustomSecurityAttributeToBronze {
    <#
    .SYNOPSIS
        Write flattened custom-security-attribute definition rows into bronze.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the custom-security-attribute taxonomy (issue #141;
        front-end schema issue ImperionCRM#575): entra_custom_security_attributes — standard
        envelope, PK (tenant_id, source, external_id) where external_id = the definition id
        (`{attributeSet}_{name}`), change-detected (unchanged content hashes are not rewritten).

        Rows are projected to exactly the applied #575 column set (Invoke-ImperionBronzePost
        -ColumnSet): missing columns land NULL, any future collector field is dropped from the
        flat projection but survives in raw_payload, so the insert can never break on collector
        drift.

        The table was prod-applied by front-end #575; until that migration is present the upsert
        fails loudly — by design (this repo never creates tables, CLAUDE.md §6; the task file's
        catch logs + exits cleanly).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionCustomSecurityAttribute (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to entra_custom_security_attributes (issue #575).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionCustomSecurityAttribute | Set-ImperionCustomSecurityAttributeToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'entra_custom_security_attributes'
    )

    begin {
        # Exact entra_custom_security_attributes column set (applied front-end #575), + envelope.
        $tableColumns = @(
            'attribute_set', 'name', 'data_type', 'status',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'm365' -ColumnSet $tableColumns
    }
}
