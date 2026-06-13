function Set-ImperionM365GroupToBronze {
    <#
    .SYNOPSIS
        Write flattened Entra/M365 group rows into the m365_groups bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the directory group inventory (issue #150,
        split from #139; front-end migration 0079 / issue #257): m365_groups — standard
        envelope, PK (tenant_id, source, external_id) where external_id = the Entra group
        object id, change-detected (unchanged content hashes are not rewritten).

        Rows are projected to exactly the migration-0079 column set
        (Invoke-ImperionBronzePost -ColumnSet): missing columns land NULL, any future
        collector field is dropped from the flat projection but survives in raw_payload,
        so the insert can never break on collector drift.

        SCHEMA GATE: migration 0079 is applied to prod (2026-06-12); were the table ever
        absent the upsert fails loudly — by design (the task file's catch logs + exits
        cleanly; this repo never creates tables, CLAUDE.md §6).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionM365Group (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to m365_groups (front-end migration 0079).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionM365Group | Set-ImperionM365GroupToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'm365_groups'
    )

    begin {
        # Exact m365_groups column set (front-end migration 0079), then the standard envelope.
        $tableColumns = @(
            'display_name', 'mail_nickname', 'mail', 'description', 'group_types',
            'security_enabled', 'mail_enabled', 'visibility', 'classification',
            'is_assignable_to_role', 'membership_rule', 'membership_rule_processing_state',
            'on_premises_sync_enabled', 'created_date_time', 'renewed_date_time',
            'expiration_date_time',
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
