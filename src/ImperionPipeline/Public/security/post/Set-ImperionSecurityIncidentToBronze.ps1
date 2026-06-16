function Set-ImperionSecurityIncidentToBronze {
    <#
    .SYNOPSIS
        Route flattened security rows into the m365_incidents / m365_alerts / m365_evidence bronze tables (multi-table writer).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the Microsoft security-incident bronze set (issue #196,
        ADR-0019; front-end migration 0119): m365_incidents, m365_alerts, m365_evidence — standard
        envelope, PK (tenant_id, source, external_id), change-detected (unchanged content hashes are
        not rewritten).

        Each incoming row is routed by its 'entity' discriminator (stamped by
        Get-ImperionSecurityIncident; the -Entity parameter covers homogeneous batches without one),
        then projected to exactly that table's migration-0119 column set — the discriminator and any
        future collector field are dropped from the flat projection (they survive in raw_payload).
        Unknown entities fail loudly (CLAUDE.md §6: schema is owned by the front-end repo; this never
        invents a table).

        PARENT→CHILD LINKAGE (ADR-0019 §1) is carried in the FE-provisioned columns, NOT enforced
        here: m365_alerts.incident_id → m365_incidents.incident_id, and m365_evidence.alert_id →
        m365_alerts.alert_id. The Microsoft↔Autotask correlation key m365_incidents.autotask_ticket_ref
        is written RAW exactly as the collector captured it — format UNCONFIRMED, the ADR-0019
        CONFIRM-BEFORE-LIVE gate. Silver stitches MS + Autotask later; this writer only lands bronze.

        SCHEMA OWNERSHIP: the m365_* tables are owned by the front-end repo (system CLAUDE.md §1) —
        this PR does NOT add a migration. Front-end migration 0119 is SHIPPED + prod-applied, so this
        writer is unblocked. It NEVER creates a table; until a table exists the upsert fails loudly —
        by design (the task file's catch logs + exits cleanly).

        Multi-table router (issue #105 pattern, mirrors Set-ImperionDefenderToBronze):
        batch-level ShouldProcess gate + connection lifecycle here, per-table projection + upsert +
        metric log via Invoke-ImperionBronzePost in its ungated router mode. Idempotent/resumable.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionSecurityIncident (accepted from the pipeline).
    .PARAMETER Entity
        Default entity for rows that carry no 'entity' property: incidents, alerts, or evidence.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .OUTPUTS
        The combined upsert tally { scanned; inserted; updated; unchanged } summed across the routed
        tables (per-table tallies are metric-logged).
    .EXAMPLE
        Get-ImperionSecurityIncident | Set-ImperionSecurityIncidentToBronze
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
        # Exact column sets of the m365_* tables (front-end migration 0119, ADR-0019).
        $tableSpecs = @{
            incidents = @{ Table = 'm365_incidents'
                Columns = @('incident_id', 'title', 'severity', 'status', 'classification',
                    'autotask_ticket_ref', 'assigned_to', 'created_at', 'last_update_at') + $standardEnvelope }
            alerts    = @{ Table = 'm365_alerts'
                Columns = @('alert_id', 'incident_id', 'title', 'severity', 'category',
                    'mitre_techniques', 'detection_source', 'created_at') + $standardEnvelope }
            evidence  = @{ Table = 'm365_evidence'
                Columns = @('evidence_id', 'alert_id', 'evidence_type', 'entity_value',
                    'verdict', 'remediation_status') + $standardEnvelope }
        }
        if ($Entity -and -not $tableSpecs.ContainsKey($Entity)) {
            throw "Set-ImperionSecurityIncidentToBronze: unknown security entity '$Entity' — no m365 table for it in front-end migration 0119."
        }
        $rowsByEntity = [ordered]@{}
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            $rowEntity = Get-ImperionMember $r 'entity'
            if (-not $rowEntity) { $rowEntity = $Entity }
            if (-not $rowEntity) {
                throw "Set-ImperionSecurityIncidentToBronze: row has no 'entity' property and no -Entity was supplied."
            }
            if (-not $tableSpecs.ContainsKey($rowEntity)) {
                throw "Set-ImperionSecurityIncidentToBronze: unknown security entity '$rowEntity' — no m365 table for it in front-end migration 0119."
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
            Write-ImperionLog -Source 'm365' -Message 'm365 security: 0 rows to write.'
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("m365 security ($totalRows rows across $($rowsByEntity.Count) tables)", 'bronze upsert')) {
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
                    -Rows $rowsByEntity[$entityName].ToArray() -LogSource 'm365' -ColumnSet $spec.Columns
                $combined.scanned += $tally.scanned; $combined.inserted += $tally.inserted
                $combined.updated += $tally.updated; $combined.unchanged += $tally.unchanged
            }
            return [pscustomobject]$combined
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
