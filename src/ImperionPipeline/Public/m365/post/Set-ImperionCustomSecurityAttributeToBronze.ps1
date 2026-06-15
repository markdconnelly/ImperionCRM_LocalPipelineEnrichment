function Set-ImperionCustomSecurityAttributeToBronze {
    <#
    .SYNOPSIS
        Write flattened custom-security-attribute definition rows into bronze.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the custom-security-attribute taxonomy (issue #141;
        front-end schema issue ImperionCRM#259): custom_security_attribute_definitions — standard
        envelope, PK (tenant_id, source, external_id) where external_id = the definition id
        (`{attributeSet}_{name}`), change-detected (unchanged content hashes are not rewritten).

        Rows are projected to exactly the schema-#259 column set (Invoke-ImperionBronzePost
        -ColumnSet): missing columns land NULL, any future collector field is dropped from the
        flat projection but survives in raw_payload, so the insert can never break on collector
        drift.

        SCHEMA GATE: the custom_security_attribute_definitions migration lands in the front-end
        repo (issue #259); until it is applied to prod the upsert fails loudly — by design (this
        repo never creates tables, CLAUDE.md §6; the task file's catch logs + exits cleanly).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionCustomSecurityAttribute (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to custom_security_attribute_definitions (issue #259).
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
        [string] $Table = 'custom_security_attribute_definitions'
    )

    begin {
        # Exact custom_security_attribute_definitions column set (#259), then the envelope.
        $tableColumns = @(
            'attribute_set', 'attribute_name', 'description', 'type', 'status',
            'is_collection', 'is_searchable', 'use_predefined_values_only', 'allowed_values',
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
