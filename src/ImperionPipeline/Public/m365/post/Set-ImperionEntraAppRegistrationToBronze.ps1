function Set-ImperionEntraAppRegistrationToBronze {
    <#
    .SYNOPSIS
        Write flattened Entra app-registration rows into the entra_app_registrations bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for tenant-hygiene app registrations (issue #219/#142;
        front-end migration 0136 / #260): entra_app_registrations — standard envelope, PK
        (tenant_id, source, external_id) where external_id = the application object id,
        change-detected (unchanged content hashes are not rewritten).

        Rows are projected to exactly the migration-0136 column set (Invoke-ImperionBronzePost
        -ColumnSet): missing columns land NULL, any extra collector field is dropped from the
        flat projection but survives in raw_payload, so the insert can never break on collector
        drift. The credential-count / earliest-expiry / has-expired columns are the rotation
        hygiene signal a benchmark reads.

        entra_app_registrations is the front-end-owned bronze table (migration 0136, applied to
        prod; this repo never creates tables, CLAUDE.md §6). The writer still fails loudly if the
        table/grant is ever missing — by design (the sync's catch logs + exits cleanly).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionEntraAppRegistration (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to entra_app_registrations (front-end migration 0136).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionEntraAppRegistration | Set-ImperionEntraAppRegistrationToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'entra_app_registrations'
    )

    begin {
        # Exact entra_app_registrations column set (front-end migration 0136), then the envelope.
        $tableColumns = @(
            'app_id', 'display_name', 'sign_in_audience', 'publisher_domain', 'created_date_time',
            'key_credential_count', 'password_credential_count',
            'earliest_credential_expiry', 'has_expired_credential',
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
