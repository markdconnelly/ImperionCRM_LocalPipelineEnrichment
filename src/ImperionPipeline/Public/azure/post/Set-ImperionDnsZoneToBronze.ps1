function Set-ImperionDnsZoneToBronze {
    <#
    .SYNOPSIS
        Route flattened DNS rows into the dns_zones / dns_records bronze tables (multi-table writer).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the DNS-posture bronze set (front-end migration
        0080 / ADR-0063): dns_zones, dns_records — standard envelope, PK
        (tenant_id, source, external_id), change-detected (unchanged content hashes are not
        rewritten).

        Each incoming row is routed by its 'entity' discriminator (stamped by
        Get-ImperionDnsZoneObject; the -Entity parameter covers homogeneous batches without
        one), then projected to exactly that table's migration-0080 column set — the
        discriminator and any future collector field are dropped from the flat projection
        (they survive in raw_payload). Unknown entities fail loudly (CLAUDE.md §6: schema is
        owned by the front-end repo; this never invents a table).

        This writer touches only the two bronze tables; the silver dns_golden / dns_domain
        pair is written by the golden-approval cmdlet and the drift merge (local #157), not
        the collector.

        SCHEMA GATE: until migration 0080 is applied to prod, the upsert fails loudly — by
        design (the task file's catch logs + exits cleanly).

        Multi-table router (issue #105 pattern, mirrors Set-ImperionDefenderToBronze):
        batch-level ShouldProcess gate + connection lifecycle here, per-table projection +
        upsert + metric log via Invoke-ImperionBronzePost. Idempotent/resumable. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionDnsZoneObject (accepted from the pipeline).
    .PARAMETER Entity
        Default entity for rows that carry no 'entity' property: zones or records.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .OUTPUTS
        The combined upsert tally { scanned; inserted; updated; unchanged } summed across the
        routed tables (per-table tallies are metric-logged).
    .EXAMPLE
        Get-ImperionDnsZoneObject -SubscriptionId $sub | Set-ImperionDnsZoneToBronze
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
        # Exact column sets of the dns_* bronze tables (front-end migration 0080).
        $tableSpecs = @{
            zones   = @{ Table = 'dns_zones'
                Columns = @('domain', 'in_azure', 'manageable', 'resource_group',
                    'subscription_id', 'ns_records', 'verdict') + $standardEnvelope }
            records = @{ Table = 'dns_records'
                Columns = @('domain', 'plane', 'record_type', 'name', 'value', 'ttl') + $standardEnvelope }
        }
        if ($Entity -and -not $tableSpecs.ContainsKey($Entity)) {
            throw "Set-ImperionDnsZoneToBronze: unknown DNS entity '$Entity' — no dns table for it in front-end migration 0080."
        }
        $rowsByEntity = [ordered]@{}
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            $rowEntity = Get-ImperionMember $r 'entity'
            if (-not $rowEntity) { $rowEntity = $Entity }
            if (-not $rowEntity) {
                throw "Set-ImperionDnsZoneToBronze: row has no 'entity' property and no -Entity was supplied."
            }
            if (-not $tableSpecs.ContainsKey($rowEntity)) {
                throw "Set-ImperionDnsZoneToBronze: unknown DNS entity '$rowEntity' — no dns table for it in front-end migration 0080."
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
            Write-ImperionLog -Source 'dns' -Message 'dns_*: 0 rows to write.'
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("dns_* ($totalRows rows across $($rowsByEntity.Count) tables)", 'bronze upsert')) {
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
                    -Rows $rowsByEntity[$entityName].ToArray() -LogSource 'dns' -ColumnSet $spec.Columns
                $combined.scanned += $tally.scanned; $combined.inserted += $tally.inserted
                $combined.updated += $tally.updated; $combined.unchanged += $tally.unchanged
            }
            return [pscustomobject]$combined
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
