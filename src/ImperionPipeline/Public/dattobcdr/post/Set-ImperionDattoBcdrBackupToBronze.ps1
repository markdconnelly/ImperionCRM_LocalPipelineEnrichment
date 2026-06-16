function Set-ImperionDattoBcdrBackupToBronze {
    <#
    .SYNOPSIS
        Write flattened Datto BCDR backup-posture rows into the datto_bcdr_backups bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for Datto BCDR (issue #195, ADR-0018). Takes the flat rows
        produced by Get-ImperionDattoBcdrBackup and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the datto_bcdr_backups column set before
        the upsert, so a corrected collector field can never break the insert; anything extra
        survives in raw_payload.

        SCHEMA OWNERSHIP: datto_bcdr_backups is owned by the front-end repo (system CLAUDE.md §1) —
        this PR does NOT add a migration. Front-end migration 0119 (front-end #674) is SHIPPED +
        prod-applied, so this writer is unblocked. NEVER creates the table; fails loudly if absent
        (ADR-0005). DOWNSTREAM CONSUMER: the silver `device` merge contributes these backup-posture
        fields to the unified device (ADR-0018 §2 field-scoped merge, joining on device_uid) — a
        cloud Pipeline / front-end concern, NOT implemented here.

        Thin adapter over Invoke-ImperionBronzePost (the shared post-writer scaffold, issue #105).
        Idempotent/resumable on external_id (the device UID). Pass an open -Connection to share one
        across a batch; otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionDattoBcdrBackup (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to datto_bcdr_backups (front-end migration 0119).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionDattoBcdrBackup | Set-ImperionDattoBcdrBackupToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'datto_bcdr_backups'
    )

    begin {
        # Exact column set of datto_bcdr_backups (front-end migration 0119): flat backup-posture
        # columns first, then the standard envelope.
        $tableColumns = @(
            'device_uid', 'protected_status', 'last_backup_at', 'last_good_backup_at',
            'backup_type', 'agent_version',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'datto_bcdr' -ColumnSet $tableColumns
    }
}
