function ConvertTo-ImperionCloudAssetCategory {
    <#
    .SYNOPSIS
        Map an Azure ARM native type to a silver cloud_asset_category (parity with the cloud
        Pipeline's normalizeCloudAssetCategory).
    .DESCRIPTION
        Module-internal helper (not exported). Keyed on the lowercased `Microsoft.<Namespace>`
        part of an ARM resource type so it is provider-version stable; unknown/empty/malformed
        types fall through to `other`. The namespace→category table is a PINNED CONTRACT,
        byte-equivalent to `merge-cloud-asset.ts` NAMESPACE_CATEGORY — a Pester test pins it;
        if one changes, change both.
    .PARAMETER NativeType
        The ARM resource type, e.g. 'Microsoft.Compute/virtualMachines'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $NativeType
    )

    # PINNED — keep byte-equivalent to ImperionCRM_Pipeline src/shared/merge-cloud-asset.ts.
    $namespaceCategory = @{
        compute             = 'compute'
        containerservice    = 'compute'
        containerinstance   = 'compute'
        containerregistry   = 'compute'
        batch               = 'compute'
        storage             = 'storage'
        netapp              = 'storage'
        network             = 'network'
        cdn                 = 'network'
        sql                 = 'database'
        dbforpostgresql     = 'database'
        dbformysql          = 'database'
        dbformariadb        = 'database'
        documentdb          = 'database'
        cache               = 'database'
        managedidentity     = 'identity'
        aad                 = 'identity'
        azureactivedirectory = 'identity'
        web                 = 'web'
        appplatform         = 'web'
        synapse             = 'analytics'
        datafactory         = 'analytics'
        databricks          = 'analytics'
        kusto               = 'analytics'
        streamanalytics     = 'analytics'
        insights            = 'analytics'
        servicebus          = 'integration'
        eventhub            = 'integration'
        eventgrid           = 'integration'
        logic               = 'integration'
        apimanagement       = 'integration'
        keyvault            = 'security'
        security            = 'security'
        resources           = 'management'
        automation          = 'management'
        operationalinsights = 'management'
        recoveryservices    = 'management'
        portal              = 'management'
        management          = 'management'
    }

    if ([string]::IsNullOrEmpty($NativeType)) { return 'other' }
    $slash = $NativeType.IndexOf('/')
    $head = if ($slash -eq -1) { $NativeType } else { $NativeType.Substring(0, $slash) }
    $head = $head.ToLower()
    $namespace = if ($head.StartsWith('microsoft.')) { $head.Substring('microsoft.'.Length) } else { $head }
    if ($namespaceCategory.ContainsKey($namespace)) { return $namespaceCategory[$namespace] }
    return 'other'
}

function Invoke-ImperionCloudAssetMerge {
    <#
    .SYNOPSIS
        Fold the Azure ARM cloud-resource bronze into the provider-agnostic silver cloud_asset
        the CMDB cloud CI arm reads — the on-prem twin of the cloud's mergeCloudAssetSources.
    .DESCRIPTION
        ADR-0026 (merge-co-locates-with-ingestion) migration 2: the local pipeline already
        INGESTS the Azure ARM bronze (scheduled-tasks/azure/cloud-resources → cloud_resources,
        ADR-0023), so it owns the bronze→silver merge too — removing the cloud-deploy coupling
        that otherwise leaves cloud_asset empty. Ported from ImperionCRM_Pipeline
        `src/shared/merge-cloud-asset.ts` (front-end #874 / migration 0139; CMDB ADR-0097).

        Mapping (1:1, no cross-source precedence — mirrors the device/expense merges):
          cloud_resources (azure_arm) → cloud_asset (provider='azure', source='azure_arm')
        external_id=ARM resource id, native_type=bronze `type`, category=normalized via
        ConvertTo-ImperionCloudAssetCategory, region=`location`, subscription_ref=
        `subscription_id`, last_seen_at=`collected_at`. The owning account resolves via
        `account_tenant` (tenant_id→account_id); it stays NULL when the tenant is unmapped —
        the row is KEPT (the CMDB view filters nulls), so an unmapped tenant's assets simply
        don't surface until the mapping lands (exactly like the device merge's deferral).

        Idempotent: upsert on the silver UNIQUE (provider, external_id) via ON CONFLICT, so the
        merge converges and never duplicates — safe to run every cadence and safe to run
        concurrently with the cloud copy during cutover (both upsert the same key). Each row
        upserts independently so one bad row never blocks the rest. Provider-agnostic by
        construction. Requires Initialize-ImperionContext.

        0 rows until front-end migration 0139 is applied AND the ARM collector (ADR-0023) has
        written bronze; CMDB cloud stays empty until `account_tenant` maps a tenant to an account.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionCloudAssetMerge
    .EXAMPLE
        Invoke-ImperionCloudAssetMerge -WhatIf   # show the plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('cloud_resources (azure_arm) bronze', 'merge to silver cloud_asset')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # account_id resolves in the read (LEFT JOIN), so an unmapped tenant yields NULL and is
        # kept (the CMDB filters nulls). tags is jsonb in bronze (#237) — read as text, re-cast
        # on write. collected_at is bronze text (loader-written ISO).
        $rows = Invoke-ImperionDbQuery -Connection $Connection -Sql @"
SELECT cr.external_id, cr.name, cr.type, cr.location, cr.sku, cr.resource_group,
       cr.subscription_id, cr.tags::text AS tags, cr.tenant_id, cr.source, cr.collected_at,
       at.account_id::text AS account_id
  FROM cloud_resources cr
  LEFT JOIN account_tenant at ON at.tenant_id = cr.tenant_id
"@

        if (-not $rows -or @($rows).Count -eq 0) {
            Write-ImperionLog -Source 'azure' -Message 'Cloud asset merge: no cloud_resources bronze rows.'
            return [pscustomobject]@{ resources = 0; merged = 0; failed = 0 }
        }

        # Idempotent upsert on the silver UNIQUE (provider, external_id) — byte-equivalent to
        # the cloud merge's ON CONFLICT (so the two converge identically during cutover).
        $upsertSql = @"
INSERT INTO cloud_asset (
    provider, external_id, name, native_type, category, region, resource_group,
    subscription_ref, sku, tags, tenant_id, source, account_id, last_seen_at
)
VALUES (
    'azure', @external_id, @name, @native_type, @category::cloud_asset_category, @region, @resource_group,
    @subscription_ref, @sku, @tags::jsonb, @tenant_id, @source, @account_id::uuid,
    COALESCE(@last_seen_at::timestamptz, now())
)
ON CONFLICT (provider, external_id) DO UPDATE SET
    name             = EXCLUDED.name,
    native_type      = EXCLUDED.native_type,
    category         = EXCLUDED.category,
    region           = EXCLUDED.region,
    resource_group   = EXCLUDED.resource_group,
    subscription_ref = EXCLUDED.subscription_ref,
    sku              = EXCLUDED.sku,
    tags             = EXCLUDED.tags,
    tenant_id        = EXCLUDED.tenant_id,
    source           = EXCLUDED.source,
    account_id       = EXCLUDED.account_id,
    last_seen_at     = EXCLUDED.last_seen_at,
    updated_at       = now()
"@

        $merged = 0
        $failed = 0
        foreach ($r in $rows) {
            if (-not $PSCmdlet.ShouldProcess($r.external_id, 'Upsert cloud_asset')) { continue }
            # collected_at is bronze text — guard the cast (posture/meta-merge pattern): junk
            # lands now() via COALESCE, never throws.
            $lastSeen = if ($r.collected_at -and [string]$r.collected_at -match '^\d{4}-\d{2}-\d{2}') { [string]$r.collected_at } else { $null }
            $params = @{
                external_id      = [string]$r.external_id
                name             = $r.name
                native_type      = $r.type
                category         = ConvertTo-ImperionCloudAssetCategory -NativeType ([string]$r.type)
                region           = $r.location
                resource_group   = $r.resource_group
                subscription_ref = $r.subscription_id
                sku              = $r.sku
                tags             = $r.tags
                tenant_id        = [string]$r.tenant_id
                source           = $r.source
                account_id       = if ($r.account_id) { [string]$r.account_id } else { $null }
                last_seen_at     = $lastSeen
            }
            try {
                Invoke-ImperionDbNonQuery -Connection $Connection -Sql $upsertSql -Parameters $params | Out-Null
                $merged++
            }
            catch {
                # One bad row never blocks the rest: log and continue; the next run retries.
                $failed++
                Write-ImperionLog -Level Error -Source 'azure' `
                    -Message "Cloud asset merge failed for resource $($r.external_id) - skipped." `
                    -Data @{ external_id = $r.external_id; error = $_.Exception.Message }
            }
        }

        Write-ImperionLog -Level Metric -Source 'azure' -Message 'Cloud asset merge complete.' -Data @{
            resources = @($rows).Count
            merged    = $merged
            failed    = $failed
            seconds   = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
        return [pscustomobject]@{ resources = @($rows).Count; merged = $merged; failed = $failed }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
