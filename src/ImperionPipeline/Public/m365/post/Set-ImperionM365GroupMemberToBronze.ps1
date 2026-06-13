function Set-ImperionM365GroupMemberToBronze {
    <#
    .SYNOPSIS
        Write flattened Entra/M365 group membership edges into the m365_group_members bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for directory group membership (issue #139;
        front-end migration 0079 / issue #257): m365_group_members — standard envelope, PK
        (tenant_id, source, external_id) where external_id = the '<group id>/<member id>'
        composite, change-detected (unchanged content hashes are not rewritten).

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
        Flat bronze edge rows from Get-ImperionM365GroupMember (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to m365_group_members (front-end migration 0079).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionM365GroupMember | Set-ImperionM365GroupMemberToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'm365_group_members'
    )

    begin {
        # Exact m365_group_members column set (front-end migration 0079), then the envelope.
        $tableColumns = @(
            'group_external_id', 'member_external_id', 'member_type',
            'member_display_name', 'member_user_principal_name', 'member_mail',
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
