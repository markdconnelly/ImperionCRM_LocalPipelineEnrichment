function Invoke-ImperionBronzePost {
    <#
    .SYNOPSIS
        The shared post-writer scaffold: shape, gate, connect, upsert, log, tally.
    .DESCRIPTION
        Module-internal engine behind every Set-Imperion*ToBronze post-layer writer
        (CLAUDE.md §6, issue #105). Owns the scaffold the writers used to repeat per copy:
        the empty-input zero tally, the ShouldProcess gate (delegated from the public
        cmdlet via -CallerCmdlet), the own-vs-reuse connection lifecycle (ADR-0003
        short-lived-token connection), the Invoke-ImperionBronzeUpsert call, and the
        metric log line. The public writers stay ~15-line adapters that collect pipeline
        rows and declare table + envelope shape + log source; behavior is identical to
        the pre-refactor copies (same tallies, same log shapes, same change-detection
        semantics).

        Three envelope shapes (ADR-0005 tables; the shape is per-table, set by the
        front-end migration that owns it):
        - Standard envelope (default): rows pass through as-is and upsert on the
          standard (tenant_id, source, external_id) key with change detection.
        - -PerSourceShape (front-end ADR-0039 tables): each row is projected down to
          { external_ref <- external_id, payload_bronze <- raw_payload } and upserted on
          external_ref with -NoChangeDetect (those tables have no content_hash column;
          change is resolved by the front-end merge).
        - -ColumnSet (over-collecting collectors, e.g. the Azure inventory set): each
          row is projected to exactly the named columns (missing ones land NULL, extras
          are dropped from the flat projection but survive in raw_payload), so a future
          collector field can never break the insert.
    .PARAMETER Rows
        The collected (non-null) flat rows to write. The public adapter owns pipeline
        collection; this function owns everything after it.
    .PARAMETER Table
        Target bronze table (must already exist — schema is owned by the front-end repo,
        ADR-0005; this never creates it).
    .PARAMETER LogSource
        Logical source key for Write-ImperionLog (e.g. 'm365', 'autotask', 'itglue').
    .PARAMETER CallerCmdlet
        The public writer's $PSCmdlet, so the caller's -WhatIf/-Confirm gate the write
        ("<table> (<n> rows)" / 'bronze upsert'). Omit ONLY when the caller has already
        passed its own ShouldProcess gate for the whole batch (the IT Glue export
        multi-table router).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse (caller disposes). When omitted, one is
        opened from config and disposed before returning.
    .PARAMETER KeyColumns
        Conflict-target override forwarded to Invoke-ImperionBronzeUpsert. When omitted,
        the upsert's standard-envelope default key applies.
    .PARAMETER JsonColumns
        jsonb-cast override forwarded to Invoke-ImperionBronzeUpsert. When omitted, the
        upsert's default (raw_payload) applies.
    .PARAMETER NoChangeDetect
        Skip the content_hash change guard (tables without a content_hash column).
        Implied by -PerSourceShape.
    .PARAMETER PerSourceShape
        Project rows to the ADR-0039 per-source shape and upsert on external_ref with
        -NoChangeDetect (see DESCRIPTION).
    .PARAMETER ColumnSet
        Project each row to exactly these columns before the upsert (see DESCRIPTION).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        # Inside a standard-envelope writer's end block:
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'autotask'
    .EXAMPLE
        # Inside an ADR-0039-shape writer's end block:
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'm365' -PerSourceShape
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'Deliberate delegation: calls ShouldProcess on the public writer''s $PSCmdlet (-CallerCmdlet) so the caller''s -WhatIf/-Confirm gate the write. Declaring SupportsShouldProcess on this module-internal helper would gate the wrong cmdlet.')]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows,
        [Parameter(Mandatory)][string] $Table,
        [Parameter(Mandatory)][string] $LogSource,
        [System.Management.Automation.PSCmdlet] $CallerCmdlet,
        $Connection,
        [string[]] $KeyColumns,
        [string[]] $JsonColumns,
        [switch] $NoChangeDetect,
        [switch] $PerSourceShape,
        [string[]] $ColumnSet
    )

    # Shape the rows for the target table's envelope.
    $rowsToWrite = $Rows
    if ($PerSourceShape) {
        $projectedRows = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $Rows) {
            $projectedRows.Add([pscustomobject]@{ external_ref = $r.external_id; payload_bronze = $r.raw_payload })
        }
        $rowsToWrite = $projectedRows.ToArray()
        $KeyColumns = @('external_ref')
        $JsonColumns = @('payload_bronze')
        $NoChangeDetect = $true
    }
    elseif ($ColumnSet) {
        $projectedRows = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $Rows) {
            $projected = [ordered]@{}
            foreach ($column in $ColumnSet) { $projected[$column] = Get-ImperionMember $r $column }
            $projectedRows.Add([pscustomobject]$projected)
        }
        $rowsToWrite = $projectedRows.ToArray()
    }

    if ($rowsToWrite.Count -eq 0) {
        Write-ImperionLog -Source $LogSource -Message "${Table}: 0 rows to write."
        return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
    }
    if ($CallerCmdlet -and -not $CallerCmdlet.ShouldProcess("$Table ($($rowsToWrite.Count) rows)", 'bronze upsert')) {
        return [pscustomobject]@{ scanned = $rowsToWrite.Count; inserted = 0; updated = 0; unchanged = 0 }
    }

    # Forward overrides only when set, so the upsert's own defaults stay in charge.
    $upsertParameters = @{ Table = $Table; Rows = $rowsToWrite }
    if ($KeyColumns) { $upsertParameters.KeyColumns = $KeyColumns }
    if ($JsonColumns) { $upsertParameters.JsonColumns = $JsonColumns }
    if ($NoChangeDetect) { $upsertParameters.NoChangeDetect = $true }

    $ownsConnection = $false
    $activeConnection = $Connection
    if (-not $activeConnection) { $activeConnection = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $tally = Invoke-ImperionBronzeUpsert -Connection $activeConnection @upsertParameters
        Write-ImperionLog -Level Metric -Source $LogSource -Message "$Table written." -Data @{
            table = $Table; scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
        }
        return $tally
    }
    finally { if ($ownsConnection) { $activeConnection.Dispose() } }
}
