function Set-ImperionDefenderToBronze {
    <#
    .SYNOPSIS
        Route flattened Defender XDR rows into the defender_incidents / defender_alerts bronze tables (multi-table writer).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the Defender XDR bronze set (front-end
        migration 0076 / ADR-0059): defender_incidents, defender_alerts — standard
        envelope, PK (tenant_id, source, external_id), change-detected (unchanged
        content hashes are not rewritten).

        Each incoming row is routed by its 'entity' discriminator (stamped by
        Get-ImperionDefenderObject; the -Entity parameter covers homogeneous batches
        without one), then projected to exactly that table's migration-0076 column set —
        the discriminator and any future collector field are dropped from the flat
        projection (they survive in raw_payload). Unknown entities fail loudly
        (CLAUDE.md §6: schema is owned by the front-end repo; this never invents a table).

        This writer NEVER touches defender_incident_ticket_link — the incident↔Autotask
        pairing lives outside bronze and is written by the linking flows, not the
        collector (front-end ADR-0059).

        SCHEMA GATE: until migration 0076 is applied to prod, the upsert fails loudly —
        by design (the task file's catch logs + exits cleanly).

        Multi-table router (issue #105 pattern, mirrors Set-ImperionSentinelToBronze):
        batch-level ShouldProcess gate + connection lifecycle here, per-table projection +
        upsert + metric log via Invoke-ImperionBronzePost in its ungated router mode.
        Idempotent/resumable. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionDefenderObject (accepted from the pipeline).
    .PARAMETER Entity
        Default entity for rows that carry no 'entity' property: incidents or alerts.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .OUTPUTS
        The combined upsert tally { scanned; inserted; updated; unchanged } summed across
        the routed tables (per-table tallies are metric-logged).
    .EXAMPLE
        Get-ImperionDefenderObject | Set-ImperionDefenderToBronze
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
        # Exact column sets of the defender_* tables (front-end migration 0076).
        $tableSpecs = @{
            incidents = @{ Table = 'defender_incidents'
                Columns = @('display_name', 'severity', 'status', 'classification', 'determination',
                    'assigned_to', 'redirect_incident_id', 'incident_web_url', 'custom_tags', 'system_tags',
                    'description', 'summary', 'resolving_comment',
                    'created_date_time', 'last_update_date_time') + $standardEnvelope }
            alerts    = @{ Table = 'defender_alerts'
                Columns = @('incident_external_id', 'provider_alert_id', 'title', 'severity', 'status',
                    'classification', 'determination', 'category', 'service_source', 'detection_source',
                    'detector_id', 'assigned_to', 'actor_display_name', 'threat_display_name',
                    'threat_family_name', 'mitre_techniques', 'alert_web_url', 'incident_web_url',
                    'description', 'recommended_actions', 'first_activity_date_time',
                    'last_activity_date_time', 'created_date_time', 'last_update_date_time',
                    'resolved_date_time') + $standardEnvelope }
        }
        if ($Entity -and -not $tableSpecs.ContainsKey($Entity)) {
            throw "Set-ImperionDefenderToBronze: unknown Defender entity '$Entity' — no defender table for it in front-end migration 0076."
        }
        $rowsByEntity = [ordered]@{}
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            $rowEntity = Get-ImperionMember $r 'entity'
            if (-not $rowEntity) { $rowEntity = $Entity }
            if (-not $rowEntity) {
                throw "Set-ImperionDefenderToBronze: row has no 'entity' property and no -Entity was supplied."
            }
            if (-not $tableSpecs.ContainsKey($rowEntity)) {
                throw "Set-ImperionDefenderToBronze: unknown Defender entity '$rowEntity' — no defender table for it in front-end migration 0076."
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
            Write-ImperionLog -Source 'defender' -Message 'defender_*: 0 rows to write.'
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("defender_* ($totalRows rows across $($rowsByEntity.Count) tables)", 'bronze upsert')) {
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
                    -Rows $rowsByEntity[$entityName].ToArray() -LogSource 'defender' -ColumnSet $spec.Columns
                $combined.scanned += $tally.scanned; $combined.inserted += $tally.inserted
                $combined.updated += $tally.updated; $combined.unchanged += $tally.unchanged
            }
            return [pscustomobject]$combined
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
