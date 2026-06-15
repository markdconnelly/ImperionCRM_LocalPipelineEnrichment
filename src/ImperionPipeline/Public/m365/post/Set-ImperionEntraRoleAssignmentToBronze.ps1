function Set-ImperionEntraRoleAssignmentToBronze {
    <#
    .SYNOPSIS
        Write flattened Entra role-assignment rows into the entra_role_assignments bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for tenant-hygiene privileged-access (issue #142;
        front-end schema issue #260): entra_role_assignments — standard envelope, PK
        (tenant_id, source, external_id) where external_id = the role-assignment id,
        change-detected (unchanged content hashes are not rewritten).

        Rows are projected to exactly the schema-#260 column set (Invoke-ImperionBronzePost
        -ColumnSet): missing columns land NULL, any future collector field is dropped from the
        flat projection but survives in raw_payload, so the insert can never break on collector
        drift. role_display_name + principal_type are the hygiene signal a benchmark reads.

        SCHEMA GATE: the entra_role_assignments migration lands in the front-end repo
        (issue #260); until applied to prod the upsert fails loudly — by design (this repo
        never creates tables, CLAUDE.md §6; the task file's catch logs + exits cleanly).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionEntraRoleAssignment (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to entra_role_assignments (front-end schema issue #260).
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
        # Exact entra_role_assignments column set (front-end schema issue #260), then the envelope.
        $tableColumns = @(
            'role_definition_id', 'role_display_name', 'role_is_builtin', 'role_template_id',
            'principal_id', 'principal_display_name', 'principal_type', 'principal_upn',
            'directory_scope_id', 'app_scope_id',
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
