function Set-ImperionCloudResourceToBronze {
    <#
    .SYNOPSIS
        Route flattened cloud-resource rows into the cloud_subscriptions / cloud_resource_groups
        / cloud_resources bronze tables (multi-table writer).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the per-client Azure ARM cloud-resource bronze set
        — slice 1 of epic #201 (ADR-0023), the CMDB cloud-asset CI source. Standard envelope,
        PK (tenant_id, source, external_id), change-detected (unchanged content hashes are not
        rewritten).

        DISTINCT from Set-ImperionAzureResourceToBronze: that writer lands the PARTNER-tenant,
        posture-scoped azure_resources set (ADR-0008 / migration 0038); THIS writer lands the
        NEW per-client cloud_* set for the CMDB. Source key 'azure_arm'.

        Each incoming row is routed by its 'entity' discriminator (stamped by
        Get-ImperionCloudResource; the -Entity parameter covers homogeneous batches without
        one), then projected to exactly that table's front-end-migration column set — the
        discriminator and any future collector field are dropped from the flat projection
        (they survive in raw_payload). Unknown entities fail loudly (CLAUDE.md §6: schema is
        owned by the front-end repo; this never invents a table).

        SCHEMA GATE (dormant-safe, ADR-0023 §3): until the front-end cloud_* migration is
        applied to prod the upsert fails loudly — by design (the task file's catch logs a Warn
        and exits cleanly). The collector merges dormant until that migration lands.

        Multi-table router (issue #105 pattern, mirrors Set-ImperionDnsZoneToBronze):
        batch-level ShouldProcess gate + connection lifecycle here, per-table projection +
        upsert + metric log via Invoke-ImperionBronzePost. Idempotent/resumable. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionCloudResource (accepted from the pipeline).
    .PARAMETER Entity
        Default entity for rows that carry no 'entity' property: subscriptions, resource_groups,
        or resources.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .OUTPUTS
        The combined upsert tally { scanned; inserted; updated; unchanged } summed across the
        routed tables (per-table tallies are metric-logged).
    .EXAMPLE
        Get-ImperionCloudResource -TenantId $clientTenant | Set-ImperionCloudResourceToBronze
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
        # Exact column sets of the cloud_* bronze tables (front-end cloud_resource* migration).
        # Json = columns cast to jsonb on write (the upsert default is raw_payload only). The
        # ARM `tags` column is jsonb (migration 0130) and the collector emits a JSON string for
        # it (ConvertTo-ImperionTagJson), so it must be cast alongside raw_payload (#237).
        $tableSpecs = @{
            subscriptions   = @{ Table = 'cloud_subscriptions'
                Columns = @('display_name', 'state', 'sub_tenant_id') + $standardEnvelope
                Json = @('raw_payload') }
            resource_groups = @{ Table = 'cloud_resource_groups'
                Columns = @('name', 'location', 'subscription_id', 'provisioning_state', 'tags') + $standardEnvelope
                Json = @('raw_payload', 'tags') }
            resources       = @{ Table = 'cloud_resources'
                Columns = @('name', 'type', 'location', 'kind', 'sku', 'resource_group',
                    'subscription_id', 'tags') + $standardEnvelope
                Json = @('raw_payload', 'tags') }
        }
        if ($Entity -and -not $tableSpecs.ContainsKey($Entity)) {
            throw "Set-ImperionCloudResourceToBronze: unknown cloud entity '$Entity' — no cloud_* table for it in the front-end migration."
        }
        $rowsByEntity = [ordered]@{}
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            $rowEntity = Get-ImperionMember $r 'entity'
            if (-not $rowEntity) { $rowEntity = $Entity }
            if (-not $rowEntity) {
                throw "Set-ImperionCloudResourceToBronze: row has no 'entity' property and no -Entity was supplied."
            }
            if (-not $tableSpecs.ContainsKey($rowEntity)) {
                throw "Set-ImperionCloudResourceToBronze: unknown cloud entity '$rowEntity' — no cloud_* table for it in the front-end migration."
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
            Write-ImperionLog -Source 'azure_arm' -Message 'cloud_*: 0 rows to write.'
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("cloud_* ($totalRows rows across $($rowsByEntity.Count) tables)", 'bronze upsert')) {
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
                    -Rows $rowsByEntity[$entityName].ToArray() -LogSource 'azure_arm' `
                    -ColumnSet $spec.Columns -JsonColumns $spec.Json
                $combined.scanned += $tally.scanned; $combined.inserted += $tally.inserted
                $combined.updated += $tally.updated; $combined.unchanged += $tally.unchanged
            }
            return [pscustomobject]$combined
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
