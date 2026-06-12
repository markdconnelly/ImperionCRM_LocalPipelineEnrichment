function Set-ImperionSentinelToBronze {
    <#
    .SYNOPSIS
        Route flattened Sentinel object rows into their sentinel_* bronze tables (multi-table writer).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the Sentinel bronze set (front-end migration
        0038): sentinel_analytic_rules, sentinel_automation_rules, sentinel_watchlists,
        sentinel_workbooks — standard envelope, PK (tenant_id, source, external_id),
        change-detected (unchanged content hashes are not rewritten).

        Each incoming row is routed by its 'entity' discriminator (stamped by
        Get-ImperionSentinelObject; the -Entity parameter covers homogeneous batches
        without one), then projected to exactly that table's migration-0038 column set —
        the discriminator and any future collector field are dropped from the flat
        projection (they survive in raw_payload). Unknown entities fail loudly
        (CLAUDE.md §6: schema is owned by the front-end repo; this never invents a table).

        Multi-table router (issue #105 pattern, mirrors Invoke-ImperionITGlueExportToBronze):
        it keeps its own batch-level ShouldProcess gate and connection lifecycle, then
        delegates each routed table's projection + upsert + metric log to the shared
        scaffold Invoke-ImperionBronzePost in its ungated router mode.

        Idempotent/resumable. Pass an open -Connection to share one across the whole
        batch; otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionSentinelObject (accepted from the pipeline).
    .PARAMETER Entity
        Default entity for rows that carry no 'entity' property. One of: analytic_rules,
        automation_rules, watchlists, workbooks.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .OUTPUTS
        The combined upsert tally { scanned; inserted; updated; unchanged } summed across
        the routed tables (per-table tallies are metric-logged).
    .EXAMPLE
        Get-ImperionSentinelObject | Set-ImperionSentinelToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        [string] $Entity,
        $Connection
    )

    begin {
        $standardEnvelope = @('tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash')
        # Exact column sets of the sentinel_* tables (front-end migration 0038).
        $tableSpecs = @{
            analytic_rules   = @{ Table = 'sentinel_analytic_rules'
                Columns = @('name', 'display_name', 'rule_kind', 'enabled', 'severity', 'tactics', 'last_modified', 'workspace') + $standardEnvelope }
            automation_rules = @{ Table = 'sentinel_automation_rules'
                Columns = @('display_name', 'rule_order', 'workspace') + $standardEnvelope }
            watchlists       = @{ Table = 'sentinel_watchlists'
                Columns = @('display_name', 'provider', 'ws_source', 'updated', 'workspace') + $standardEnvelope }
            workbooks        = @{ Table = 'sentinel_workbooks'
                Columns = @('display_name', 'category', 'version', 'time_modified', 'subscription_id') + $standardEnvelope }
        }
        if ($Entity -and -not $tableSpecs.ContainsKey($Entity)) {
            throw "Set-ImperionSentinelToBronze: unknown Sentinel entity '$Entity' — no sentinel table for it in front-end migration 0038."
        }
        $rowsByEntity = [ordered]@{}
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            $rowEntity = Get-ImperionMember $r 'entity'
            if (-not $rowEntity) { $rowEntity = $Entity }
            if (-not $rowEntity) {
                throw "Set-ImperionSentinelToBronze: row has no 'entity' property and no -Entity was supplied."
            }
            if (-not $tableSpecs.ContainsKey($rowEntity)) {
                throw "Set-ImperionSentinelToBronze: unknown Sentinel entity '$rowEntity' — no sentinel table for it in front-end migration 0038."
            }
            if (-not $rowsByEntity.Contains($rowEntity)) {
                $rowsByEntity[$rowEntity] = [System.Collections.Generic.List[object]]::new()
            }
            $rowsByEntity[$rowEntity].Add($r)
        }
    }
    end {
        $totalRows = 0
        foreach ($entityRows in $rowsByEntity.Values) { $totalRows += $entityRows.Count }
        if ($totalRows -eq 0) {
            Write-ImperionLog -Source 'sentinel' -Message 'sentinel_*: 0 rows to write.'
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("sentinel_* ($totalRows rows across $($rowsByEntity.Count) tables)", 'bronze upsert')) {
            return [pscustomobject]@{ scanned = $totalRows; inserted = 0; updated = 0; unchanged = 0 }
        }

        $ownsConnection = $false
        $conn = $Connection
        if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
        try {
            $combined = [ordered]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
            foreach ($entityName in $rowsByEntity.Keys) {
                $spec = $tableSpecs[$entityName]
                $tally = Invoke-ImperionBronzePost -Connection $conn -Table $spec.Table `
                    -Rows $rowsByEntity[$entityName].ToArray() -LogSource 'sentinel' -ColumnSet $spec.Columns
                $combined.scanned += $tally.scanned; $combined.inserted += $tally.inserted
                $combined.updated += $tally.updated; $combined.unchanged += $tally.unchanged
            }
            return [pscustomobject]$combined
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
