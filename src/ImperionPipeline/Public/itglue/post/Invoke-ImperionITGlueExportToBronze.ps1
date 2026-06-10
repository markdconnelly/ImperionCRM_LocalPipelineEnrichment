function Invoke-ImperionITGlueExportToBronze {
    <#
    .SYNOPSIS
        Route IT Glue dataset-export rows into their itglue_export_* bronze tables (multi-table writer).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the IT Glue full-export table set (front-end
        migration 0038): one itglue_export_<entity> table per export entity, all sharing the
        generic export envelope { source, external_id, organization_id, name, resource_url,
        created_at, updated_at, collected_at, raw_payload, content_hash } keyed on
        (source, external_id) — the same row shape Invoke-ImperionITGlueExport flattens to.

        Each incoming row is routed by its export entity — either a per-row 'entity' property
        (stripped before the upsert; the table has no such column) or the -Entity parameter for
        homogeneous batches — then upserted per table with change detection (unchanged content
        hashes are not rewritten). Unknown entities fail loudly (CLAUDE.md §6: schema is owned
        by the front-end repo; this never invents a table). Relationship edges
        (itglue_export_relationship) are not written here — they stay with
        Invoke-ImperionITGlueExport's delete-then-insert pass, which owns the full snapshot.

        Idempotent/resumable. Pass an open -Connection to share one across the whole batch;
        otherwise a connection is opened per call and disposed. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Export-envelope rows (from the pipeline). Each row may carry an 'entity' property
        naming its export entity (e.g. 'organizations'); rows without one use -Entity.
    .PARAMETER Entity
        Default export entity for rows that carry no 'entity' property. One of: organizations,
        configurations, contacts, locations, flexible_asset_types, flexible_assets, domains,
        manufacturers, models, operating_systems, configuration_types, organization_types,
        organization_statuses.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .OUTPUTS
        The combined upsert tally { scanned; inserted; updated; unchanged } summed across the
        routed tables (per-table tallies are metric-logged).
    .EXAMPLE
        $orgRows | Invoke-ImperionITGlueExportToBronze -Entity organizations
    .EXAMPLE
        # Mixed batch routed by each row's 'entity' property, one shared connection:
        $c = New-ImperionDbConnection
        $mixedExportRows | Invoke-ImperionITGlueExportToBronze -Connection $c
        $c.Dispose()
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        [string] $Entity,
        $Connection
    )

    begin {
        # The itglue_export_* table set defined by front-end migration 0038.
        $validEntities = @(
            'organizations', 'configurations', 'contacts', 'locations',
            'flexible_asset_types', 'flexible_assets', 'domains', 'manufacturers', 'models',
            'operating_systems', 'configuration_types', 'organization_types', 'organization_statuses'
        )
        if ($Entity -and $Entity -notin $validEntities) {
            throw "Invoke-ImperionITGlueExportToBronze: unknown export entity '$Entity' — no itglue_export_$Entity table in front-end migration 0038."
        }
        $rowsByEntity = [ordered]@{}
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            $rowEntity = Get-ImperionMember $r 'entity'
            if (-not $rowEntity) { $rowEntity = $Entity }
            if (-not $rowEntity) {
                throw "Invoke-ImperionITGlueExportToBronze: row has no 'entity' property and no -Entity was supplied."
            }
            if ($rowEntity -notin $validEntities) {
                throw "Invoke-ImperionITGlueExportToBronze: unknown export entity '$rowEntity' — no itglue_export_$rowEntity table in front-end migration 0038."
            }
            # Strip the routing discriminator — the export tables have no 'entity' column.
            $projected = [ordered]@{}
            foreach ($property in $r.PSObject.Properties) {
                if ($property.Name -ne 'entity') { $projected[$property.Name] = $property.Value }
            }
            if (-not $rowsByEntity.Contains($rowEntity)) {
                $rowsByEntity[$rowEntity] = [System.Collections.Generic.List[object]]::new()
            }
            $rowsByEntity[$rowEntity].Add([pscustomobject]$projected)
        }
    }
    end {
        $totalRows = 0
        foreach ($entityRows in $rowsByEntity.Values) { $totalRows += $entityRows.Count }
        if ($totalRows -eq 0) {
            Write-ImperionLog -Source 'itglue' -Message 'itglue_export_*: 0 rows to write.'
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("itglue_export_* ($totalRows rows across $($rowsByEntity.Count) tables)", 'bronze upsert')) {
            return [pscustomobject]@{ scanned = $totalRows; inserted = 0; updated = 0; unchanged = 0 }
        }

        $ownsConnection = $false
        $conn = $Connection
        if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
        try {
            $combined = [ordered]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
            foreach ($entityName in $rowsByEntity.Keys) {
                $table = "itglue_export_$entityName"
                $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table $table `
                    -Rows $rowsByEntity[$entityName].ToArray() -KeyColumns @('source', 'external_id')
                Write-ImperionLog -Level Metric -Source 'itglue' -Message "$table written." -Data @{
                    table = $table; scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
                }
                $combined.scanned += $tally.scanned; $combined.inserted += $tally.inserted
                $combined.updated += $tally.updated; $combined.unchanged += $tally.unchanged
            }
            return [pscustomobject]$combined
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
