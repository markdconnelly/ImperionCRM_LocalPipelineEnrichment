function Set-ImperionDattoRmmDeviceToBronze {
    <#
    .SYNOPSIS
        Write flattened Datto RMM device rows into the datto_rmm_devices bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for Datto RMM (issue #195, ADR-0018). Takes the flat rows
        produced by Get-ImperionDattoRmmDevice and upserts them (standard envelope,
        change-detected: unchanged content hashes are not rewritten). Each row is projected to
        exactly the datto_rmm_devices column set before the upsert, so a corrected collector field
        can never break the insert; anything extra (the full asset/software inventory) survives in
        raw_payload.

        SCHEMA OWNERSHIP: datto_rmm_devices is owned by the front-end repo (system CLAUDE.md §1) —
        this PR does NOT add a migration. Front-end migration 0119 (front-end #674) is SHIPPED +
        prod-applied, so this writer is unblocked. It NEVER creates the table; it fails loudly if
        absent (ADR-0005). DOWNSTREAM CONSUMER: the silver `device` merge (cloud Pipeline /
        front-end) places datto_rmm in the precedence `website > datto_rmm > m365 > itglue`
        (ADR-0018 §2) — NOT implemented here.

        Thin adapter over Invoke-ImperionBronzePost (the shared post-writer scaffold, issue #105).
        Idempotent/resumable on external_id (the device UID). Pass an open -Connection to share one
        across a batch; otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionDattoRmmDevice (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to datto_rmm_devices (front-end migration 0119).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionDattoRmmDevice | Set-ImperionDattoRmmDeviceToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'datto_rmm_devices'
    )

    begin {
        # Exact column set of datto_rmm_devices (front-end migration 0119): flat device columns
        # first, then the standard envelope. Extra collector fields are dropped from the flat
        # projection (they remain queryable in raw_payload).
        $tableColumns = @(
            'device_uid', 'hostname', 'site_name', 'operating_system', 'last_seen',
            'patch_status', 'antivirus_status', 'agent_version', 'device_type', 'soft_delete',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'datto_rmm' -ColumnSet $tableColumns
    }
}
