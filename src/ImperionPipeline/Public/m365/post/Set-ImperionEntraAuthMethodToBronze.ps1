function Set-ImperionEntraAuthMethodToBronze {
    <#
    .SYNOPSIS
        Write flattened per-user MFA registration rows into the entra_auth_methods bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the per-user authentication-method /
        MFA-registration feed (issue #140; front-end migration 0077 / ADR-0051 posture
        model): entra_auth_methods — standard envelope, PK (tenant_id, source,
        external_id) where external_id = the Entra user object id, change-detected
        (unchanged content hashes are not rewritten).

        Rows are projected to exactly the migration-0077 column set
        (Invoke-ImperionBronzePost -ColumnSet): missing columns land NULL, any future
        collector field is dropped from the flat projection but survives in raw_payload,
        so the insert can never break on collector drift.

        SCHEMA GATE: until migration 0077 is applied to prod, the upsert fails loudly —
        by design (the task file's catch logs + exits cleanly; this repo never creates
        tables, CLAUDE.md §6).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionEntraAuthMethod (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to entra_auth_methods (front-end migration 0077).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionEntraAuthMethod | Set-ImperionEntraAuthMethodToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'entra_auth_methods'
    )

    begin {
        # Exact entra_auth_methods column set (front-end migration 0077), then the
        # standard envelope.
        $tableColumns = @(
            'user_principal_name', 'user_display_name', 'user_type', 'is_admin',
            'is_mfa_capable', 'is_mfa_registered',
            'is_passwordless_capable',
            'is_sspr_capable', 'is_sspr_enabled', 'is_sspr_registered',
            'is_system_preferred_authentication_method_enabled',
            'system_preferred_authentication_methods',
            'methods_registered',
            'user_preferred_method_for_secondary_authentication',
            'last_updated_date_time',
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
