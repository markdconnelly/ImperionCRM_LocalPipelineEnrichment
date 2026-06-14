function Set-ImperionAutotaskTimeEntryToBronze {
    <#
    .SYNOPSIS
        Write typed Autotask TimeEntry rows into the autotask_time_entry bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for employee time tracking (front-end ADR-0082,
        migration 0086; issue #171). Takes the native-typed rows from
        Get-ImperionAutotaskTimeEntry and upserts them via Invoke-ImperionBronzePost,
        idempotent on `external_ref` (the Autotask TimeEntry id; the table's UNIQUE key).
        This is the authoritative scheduled BULK reconcile; the cloud Pipeline PL-2 handles
        the on-demand "refresh now" window (ImperionCRM_Pipeline#101).

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the gate/connection/upsert/log/tally; this declares table, column set,
        and conflict key. Three deliberate departures from the standard-envelope writers,
        because autotask_time_entry is a TYPED per-source table (not the text+jsonb envelope):
        - `-ColumnSet` projects to exactly the collector-owned columns. `app_user_id` and
          `matched_at` are OMITTED on purpose — the merge (PL-1, ImperionCRM_Pipeline#100)
          owns employee resolution, and the upsert's SET clause only touches projected
          columns, so a re-ingested row keeps its resolution.
        - `-KeyColumns external_ref` — the conflict target is the Autotask id, not the
          standard (tenant_id, source, external_id) key (those columns don't exist here).
        - `-JsonColumns payload_bronze` + `-NoChangeDetect` — payload casts to jsonb and the
          table has no content_hash column (change is resolved in the merge, ADR-0039 idiom).

        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise
        a connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Typed bronze rows from Get-ImperionAutotaskTimeEntry (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to autotask_time_entry (front-end migration 0086).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionAutotaskTimeEntry -SinceDays 7 | Set-ImperionAutotaskTimeEntryToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'autotask_time_entry'
    )

    begin {
        # Exact collector-owned column set of autotask_time_entry (front-end migration 0086).
        # app_user_id / matched_at / created_at / updated_at are intentionally absent — owned by
        # the merge and the DB, never written here.
        $tableColumns = @(
            'external_ref', 'autotask_resource_id', 'autotask_ticket_id', 'work_date',
            'started_at', 'ended_at', 'hours_worked', 'payload_bronze', 'last_seen_at'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'autotask' `
            -ColumnSet $tableColumns -KeyColumns 'external_ref' -JsonColumns 'payload_bronze' -NoChangeDetect
    }
}
