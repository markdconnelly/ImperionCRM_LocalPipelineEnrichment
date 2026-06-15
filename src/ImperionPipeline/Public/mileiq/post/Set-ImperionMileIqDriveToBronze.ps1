function Set-ImperionMileIqDriveToBronze {
    <#
    .SYNOPSIS
        Write typed MileIQ drive rows into the mileiq_drive bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for employee mileage capture (front-end ADR-0083,
        migration 0089; issue #167). Takes the native-typed rows from Get-ImperionMileIqDrive
        and upserts them via Invoke-ImperionBronzePost, idempotent on `mileiq_drive_id` (the
        stable MileIQ drive id; the table's UNIQUE key).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the gate/connection/upsert/log/tally; this declares table, column set,
        and conflict key. Three deliberate departures from the standard-envelope writers,
        because mileiq_drive is a TYPED per-source table (not the text+jsonb envelope), mirroring
        the autotask_time_entry sibling (ADR-0082):
        - `-ColumnSet` projects to exactly the collector-owned columns. `matched_at` and the
          DB-owned created_at/updated_at are OMITTED on purpose; `app_user_id` IS projected here
          (the collector resolves it from employee_profile where possible, NULL otherwise), and
          the upsert's SET clause only touches projected columns so a re-ingest converges.
        - `-KeyColumns mileiq_drive_id` — the conflict target is the MileIQ drive id, not the
          standard (tenant_id, source, external_id) key (those columns don't exist here).
        - `-JsonColumns payload_bronze` + `-NoChangeDetect` — payload casts to jsonb and the
          table has no content_hash column (change is resolved in the merge, ADR-0039 idiom).

        PERSONAL drives never reach this writer (the collector requests business-classified
        drives only, ADR-0083); no comp data is written and no PII is logged (metric counts
        only, CLAUDE.md §8). Idempotent/resumable. Pass an open -Connection to share one across
        a batch; otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Typed bronze rows from Get-ImperionMileIqDrive (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to mileiq_drive (front-end migration 0089).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionMileIqDrive -SinceDays 7 | Set-ImperionMileIqDriveToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'mileiq_drive'
    )

    begin {
        # Exact collector-owned column set of mileiq_drive (front-end migration 0089).
        # matched_at / created_at / updated_at are intentionally absent — owned by the merge and
        # the DB, never written here. app_user_id is written (NULL when unresolved).
        $tableColumns = @(
            'mileiq_drive_id', 'mileiq_user_id', 'app_user_id', 'drive_date', 'miles',
            'origin', 'destination', 'suggested_rate', 'suggested_amount',
            'payload_bronze', 'last_seen_at'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'mileiq' `
            -ColumnSet $tableColumns -KeyColumns 'mileiq_drive_id' -JsonColumns 'payload_bronze' -NoChangeDetect
    }
}
