function Set-ImperionEntraRoleAssignmentToBronze {
    <#
    .SYNOPSIS
        Write flattened Entra role-assignment rows into the entra_role_assignments bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for tenant-hygiene privileged-access (issue #219/#142;
        front-end migration 0136 / #260): entra_role_assignments — standard envelope, PK
        (tenant_id, source, external_id) where external_id = the role-assignment id,
        change-detected (unchanged content hashes are not rewritten).

        Rows are projected to exactly the migration-0136 column set (Invoke-ImperionBronzePost
        -ColumnSet): missing columns land NULL, any extra collector field is dropped from the
        flat projection but survives in raw_payload, so the insert can never break on collector
        drift. is_privileged + role_display_name + principal_type are the hygiene signal a
        benchmark reads.

        entra_role_assignments is the front-end-owned bronze table (migration 0136, applied to
        prod; this repo never creates tables, CLAUDE.md §6). The writer still fails loudly if the
        table/grant is ever missing — by design (the sync's catch logs + exits cleanly).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionEntraRoleAssignment (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to entra_role_assignments (front-end migration 0136).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionEntraRoleAssignment | Set-ImperionEntraRoleAssignmentToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'entra_role_assignments'
    )

    begin {
        # Exact entra_role_assignments column set (front-end migration 0136), then the envelope.
        $tableColumns = @(
            'role_definition_id', 'role_display_name', 'is_privileged',
            'principal_id', 'principal_type', 'principal_display_name',
            'directory_scope_id', 'assignment_type',
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
