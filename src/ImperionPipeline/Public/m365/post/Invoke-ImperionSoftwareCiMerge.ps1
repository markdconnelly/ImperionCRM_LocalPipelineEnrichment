function Invoke-ImperionSoftwareCiMerge {
    <#
    .SYNOPSIS
        Fold the Intune managed-apps bronze into the silver software_ci the CMDB software CI arm
        reads — one row per software install, resolved onto its silver device.
    .DESCRIPTION
        ADR-0026 (merge-co-locates-with-ingestion): the local pipeline INGESTS the Intune
        managed-apps bronze (Invoke-ImperionIntuneAppSync → intune_managed_apps, #252 / front-end
        migration 0148), so it owns the bronze→silver merge too. The on-prem populate twin of
        front-end #652 / PR #1331 (silver software_ci, migration 0204 — PLACEHOLDER number, real
        number claimed at merge per system CLAUDE.md §10.3).

        Grain (1:1, device-keyed — the grain of the bronze): one software_ci row per software
        INSTALL (one app on one device). Mapping:
          intune_managed_apps (source 'intune') → software_ci (source='intune')
        name=display_name, publisher, version, platform, install_state straight across;
        external_ref=intune_managed_apps.external_id; last_seen_at=bronze collected_at.

        Device resolution — the SAME keys the device CI laterals on (front-end migration 0069):
        each app row resolves to a silver `device` by `managed_device_id`
        (= intune_managed_devices.external_id — the PRIMARY device identity), with `serial_number`
        as the FALLBACK. Silver `device` exposes only `serial_number` as the Intune lateral key
        (0069 — azure_ad_device_id is not stamped yet), so the primary path reads the authoritative
        serial off the matched intune_managed_devices row and the fallback uses the app row's own
        denormalised serial; both join silver `device` on serial. account_id resolves THROUGH the
        device (device.account_id) — the same staff/internal exclusion the device inherits. An app
        whose device cannot be resolved is DROPPED (counted `unresolved`, never written) — the
        software_ci FKs (account_id, device_id) are both NOT NULL, so an unresolved row has no home;
        it simply lands once its device merges to silver.

        Idempotent: upsert on the silver UNIQUE (source, device_id, external_ref) via ON CONFLICT,
        so the merge converges and never duplicates — safe to run every cadence. Each row upserts
        independently so one bad row never blocks the rest. Requires Initialize-ImperionContext.

        0 rows until front-end migration 0204 is applied AND the Intune managed-apps collector has
        written bronze (the Mark-gated Graph DeviceManagementApps.Read.All grant + migration 0148
        prod-apply); software_ci stays empty for a device until that device merges to silver `device`.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionSoftwareCiMerge
    .EXAMPLE
        Invoke-ImperionSoftwareCiMerge -WhatIf   # show the plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('intune_managed_apps bronze', 'merge to silver software_ci')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # Resolve each app to a silver device in the read. Primary: managed_device_id =
        # intune_managed_devices.external_id (the device CI's primary lateral key, 0069) yields the
        # authoritative serial; fallback: the app row's own denormalised serial. Silver `device`
        # laterals Intune on serial only (0069), so both arms land on device by serial. account_id
        # resolves through the device. device_id NULL (no silver device yet) → dropped below.
        # name COALESCEs to app_id/external_id so the software_ci NOT NULL name is always satisfied.
        # collected_at is bronze text (loader-written ISO) — the cast is guarded on write.
        $rows = Invoke-ImperionDbQuery -Connection $Connection -Sql @"
SELECT ima.external_id AS external_ref,
       COALESCE(NULLIF(btrim(ima.display_name), ''), ima.app_id, ima.external_id) AS name,
       ima.publisher,
       ima.version,
       ima.platform,
       ima.install_state,
       ima.tenant_id,
       ima.collected_at,
       d.id::text         AS device_id,
       d.account_id::text AS account_id
  FROM intune_managed_apps ima
  LEFT JOIN intune_managed_devices imd
         ON imd.tenant_id = ima.tenant_id
        AND imd.external_id = ima.managed_device_id
        AND COALESCE(ima.managed_device_id, '') <> ''
  LEFT JOIN LATERAL (
        SELECT dev.id, dev.account_id
          FROM device dev
         WHERE dev.serial_number IS NOT NULL
           AND dev.serial_number <> ''
           AND dev.serial_number = COALESCE(NULLIF(imd.serial_number, ''), NULLIF(ima.serial_number, ''))
         ORDER BY dev.id
         LIMIT 1
       ) d ON true
 WHERE ima.external_id IS NOT NULL
"@

        if (-not $rows -or @($rows).Count -eq 0) {
            Write-ImperionLog -Source 'm365' -Message 'Software CI merge: no intune_managed_apps bronze rows.'
            return [pscustomobject]@{ apps = 0; merged = 0; unresolved = 0; failed = 0 }
        }

        # Idempotent upsert on the silver UNIQUE (source, device_id, external_ref).
        $upsertSql = @"
INSERT INTO software_ci (
    account_id, device_id, name, publisher, version, platform, install_state, source,
    external_ref, last_seen_at
)
VALUES (
    @account_id::uuid, @device_id::uuid, @name, @publisher, @version, @platform, @install_state,
    'intune', @external_ref, COALESCE(@last_seen_at::timestamptz, now())
)
ON CONFLICT (source, device_id, external_ref) DO UPDATE SET
    account_id    = EXCLUDED.account_id,
    name          = EXCLUDED.name,
    publisher     = EXCLUDED.publisher,
    version       = EXCLUDED.version,
    platform      = EXCLUDED.platform,
    install_state = EXCLUDED.install_state,
    last_seen_at  = EXCLUDED.last_seen_at,
    updated_at    = now()
"@

        $merged = 0
        $unresolved = 0
        $failed = 0
        foreach ($r in $rows) {
            # Drop apps whose device can't be resolved: software_ci.device_id/account_id are both
            # NOT NULL, so an unresolved install has no home. Lands once the device merges to silver.
            if (-not $r.device_id -or -not $r.account_id) { $unresolved++; continue }
            if (-not $PSCmdlet.ShouldProcess($r.external_ref, 'Upsert software_ci')) { continue }
            # collected_at is bronze text — guard the cast (cloud-asset/posture pattern): junk lands
            # now() via COALESCE, never throws.
            $lastSeen = if ($r.collected_at -and [string]$r.collected_at -match '^\d{4}-\d{2}-\d{2}') { [string]$r.collected_at } else { $null }
            $params = @{
                account_id    = [string]$r.account_id
                device_id     = [string]$r.device_id
                name          = $r.name
                publisher     = $r.publisher
                version       = $r.version
                platform      = $r.platform
                install_state = $r.install_state
                external_ref  = [string]$r.external_ref
                last_seen_at  = $lastSeen
            }
            try {
                Invoke-ImperionDbNonQuery -Connection $Connection -Sql $upsertSql -Parameters $params | Out-Null
                $merged++
            }
            catch {
                # One bad row never blocks the rest: log and continue; the next run retries.
                $failed++
                Write-ImperionLog -Level Error -Source 'm365' `
                    -Message "Software CI merge failed for app $($r.external_ref) - skipped." `
                    -Data @{ external_ref = $r.external_ref; error = $_.Exception.Message }
            }
        }

        Write-ImperionLog -Level Metric -Source 'm365' -Message 'Software CI merge complete.' -Data @{
            apps       = @($rows).Count
            merged     = $merged
            unresolved = $unresolved
            failed     = $failed
            seconds    = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
        return [pscustomobject]@{ apps = @($rows).Count; merged = $merged; unresolved = $unresolved; failed = $failed }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
