function Set-ImperionEntraDomainToBronze {
    <#
    .SYNOPSIS
        Write flattened Entra domain rows into the entra_domains bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for tenant-hygiene domains (issue #142; front-end
        schema issue #260): entra_domains — standard envelope, PK
        (tenant_id, source, external_id) where external_id = the domain FQDN, change-detected
        (unchanged content hashes are not rewritten).

        Rows are projected to exactly the schema-#260 column set (Invoke-ImperionBronzePost
        -ColumnSet): missing columns land NULL, any future collector field is dropped from the
        flat projection but survives in raw_payload, so the insert can never break on collector
        drift.

        SCHEMA GATE: the entra_domains migration lands in the front-end repo (issue #260);
        until it is applied to prod the upsert fails loudly — by design (this repo never
        creates tables, CLAUDE.md §6; the task file's catch logs + exits cleanly).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionEntraDomain (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to entra_domains (front-end schema issue #260).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionEntraDomain | Set-ImperionEntraDomainToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'entra_domains'
    )

    begin {
        # Exact entra_domains column set (front-end schema issue #260), then the standard envelope.
        $tableColumns = @(
            'domain_name', 'authentication_type', 'is_default', 'is_initial', 'is_root',
            'is_verified', 'is_admin_managed', 'supported_services',
            'password_validity_period_in_days', 'password_notification_window_in_days',
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
