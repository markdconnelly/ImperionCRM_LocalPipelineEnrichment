function Invoke-ImperionUniFiMerge {
    <#
    .SYNOPSIS
        Fold the UniFi network-device bronze (`unifi_devices`) into silver `device` as the
        network-infrastructure class (`device_type='network'`) — the on-prem bronze->silver
        merge for UniFi, co-located with the LP collector (#73/#259, #284).
    .DESCRIPTION
        ADR-0026 (merge-co-locates-with-ingestion): the local pipeline INGESTS the UniFi bronze
        (Invoke-ImperionUniFiDeviceSync, #259), so it owns the bronze->silver merge too. UniFi is
        the live-controller authority for the network-infrastructure device class (switches/APs/
        gateways) the endpoint sources do not see, and feeds silver `device`, NEVER `cloud_asset`
        (front-end `device` OKF concept, #1053; precedence `website > datto_rmm > unifi > m365 >
        itglue`).

        SCHEMA REALITY (ImperionCRM #1241 — filed, Mark-gated). The `device` OKF concept names
        `mac` as the UniFi lateral key, `device_type='network'`, and firmware-compliance signals
        as silver columns. The current silver `device` table has NONE of these: no `mac` column /
        no `(account_id, mac)` unique index, no `source`/precedence column (so a replace-from-
        source scoped to the `unifi` label is impossible — unlike `cloud_asset`), no firmware
        columns, and the local-pipeline role holds only SELECT (no INSERT/UPDATE). This repo never
        owns schema (CLAUDE.md §5/§6), so until #1241 lands this merge is deliberately CONSERVATIVE
        and ADDITIVE — it matches the cloud `device-matcher` name-tier + create, and NEVER
        overwrites an existing identity field (so it cannot clobber a higher-precedence
        `website`/`datto_rmm`/etc. row it has no `source` column to recognize):

          1. RESOLVE ACCOUNT. The bronze envelope `tenant_id` is, per the collector
             (Resolve-ImperionAccountTenant), the account's mapped Microsoft tenant when one
             exists, ELSE the account id itself. The merge reverses that: `account_tenant.tenant_id
             = bronze.tenant_id` -> account_id; else, when the bronze tenant_id IS a real
             `account.id`, use it directly. A row that resolves to NO account is SKIPPED (kept in
             bronze, surfaced as the unmapped count) — a network device with no owning account is
             not written (no meaningful place to put it; mirrors the device-matcher's account
             requirement for the name tier).
          2. MATCH on `(account_id, lower(btrim(name)))` — the cloud device-matcher's name tier
             (0.6), the only stable natural key available without a `mac` column. UniFi gear has
             no serial, so the serial tier does not apply.
          3. CREATE when no match: insert a new `device` with `device_type='network'`,
             `manufacturer='Ubiquiti'`, plus name/model/status/last_seen_at.
          4. COALESCE-FILL on a match: fill ONLY currently-NULL identity fields
             (device_type/manufacturer/model/status/last_seen_at). Never overwrite a non-null
             value — that is the precedence-safety guarantee while `device` has no `source`
             column: UniFi can enrich a sparse row but never demote a higher-authority source's
             field.

        Idempotent + resumable: a re-run re-matches the same name within the same account and
        re-fills the same nulls (converges, never duplicates). Each bronze row is processed inside
        its own try/catch so one bad row never blocks the rest (the cloud_asset/posture/Pax8
        precedent). Requires Initialize-ImperionContext.

        DORMANT-SAFE: 0 rows until `unifi_devices` bronze hydrates (a console registered in the
        credential registry + the collector run, Mark-gated) AND the `device` INSERT/UPDATE grant
        lands (#1241). With no bronze rows it logs and no-ops. The proper `mac`-keyed precedence
        merge + firmware-signal surfacing follow once #1241's schema lands.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionUniFiMerge
    .EXAMPLE
        Invoke-ImperionUniFiMerge -WhatIf   # show the plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('unifi_devices bronze', 'merge to silver device (network class)')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # Resolve each DISTINCT (external_id) UniFi device to its owning account in the read, so
        # PowerShell only ever sees account-resolved or explicitly-unmapped rows. account_id
        # resolves two ways (LEFT JOINs, COALESCE): (a) the bronze tenant_id is a managed-client
        # Microsoft tenant -> account_tenant.tenant_id maps it to account_id; (b) the bronze
        # tenant_id IS the account id (the collector's fallback when no MS tenant is mapped) ->
        # it matches account.id directly. NULL account_id (neither path) is left for PS to skip.
        # last_seen / adopted are all-text bronze (loader-written) — guard the timestamp cast in PS.
        $rows = Invoke-ImperionDbQuery -Connection $Connection -Sql @"
SELECT u.external_id,
       u.tenant_id,
       u.name,
       u.model,
       u.status,
       u.last_seen,
       COALESCE(at.account_id, a_direct.id)::text AS account_id
  FROM (
        SELECT DISTINCT ON (tenant_id, external_id)
               tenant_id, external_id, name, model, status, last_seen
          FROM unifi_devices
         WHERE name IS NOT NULL AND btrim(name) <> ''
         ORDER BY tenant_id, external_id, collected_at DESC
       ) u
  LEFT JOIN account_tenant at ON at.tenant_id = u.tenant_id
  LEFT JOIN account a_direct
         ON a_direct.id = NULLIF(u.tenant_id, '')::uuid
"@

        if (-not $rows -or @($rows).Count -eq 0) {
            Write-ImperionLog -Source 'unifi' -Message 'UniFi merge: no unifi_devices bronze rows.'
            return [pscustomobject]@{ devices = 0; created = 0; updated = 0; unmapped = 0; failed = 0 }
        }

        # Match on (account_id, lower(btrim(name))) — the cloud device-matcher name tier; the only
        # stable natural key without a `mac` column (#1241). Returns the existing device id, or null.
        $matchSql = @"
SELECT id::text AS id
  FROM device
 WHERE account_id = @account_id::uuid
   AND lower(btrim(name)) = lower(btrim(@name))
 LIMIT 1
"@

        # CREATE a new network device. UniFi gear has no serial -> serial_number stays null.
        $insertSql = @"
INSERT INTO device (account_id, name, device_type, manufacturer, model, status, last_seen_at)
VALUES (
    @account_id::uuid, @name, 'network', 'Ubiquiti', @model, @status,
    @last_seen_at::timestamptz
)
"@

        # COALESCE-FILL: enrich ONLY currently-null identity fields on an existing match. Never
        # overwrites a non-null value -> cannot demote a higher-precedence source's field while
        # `device` has no `source` column to recognize one (#1241). last_seen_at advances to the
        # greater of the two so a fresher UniFi sighting still counts.
        $fillSql = @"
UPDATE device
   SET device_type  = COALESCE(device_type, 'network'),
       manufacturer = COALESCE(manufacturer, 'Ubiquiti'),
       model        = COALESCE(model, @model),
       status       = COALESCE(status, @status),
       last_seen_at = GREATEST(last_seen_at, @last_seen_at::timestamptz),
       updated_at   = now()
 WHERE id = @id::uuid
"@

        $created = 0
        $updated = 0
        $unmapped = 0
        $failed = 0
        foreach ($r in $rows) {
            # No owning account (neither resolution path) -> kept in bronze, surfaced as a count.
            if ([string]::IsNullOrWhiteSpace([string]$r.account_id)) {
                $unmapped++
                continue
            }
            if (-not $PSCmdlet.ShouldProcess([string]$r.external_id, 'Merge unifi_devices -> device')) { continue }

            # last_seen is bronze text — guard the cast (cloud_asset/posture pattern): an ISO-ish
            # value passes, junk/empty -> null so the timestamptz cast never throws.
            $lastSeen = if ($r.last_seen -and [string]$r.last_seen -match '^\d{4}-\d{2}-\d{2}') { [string]$r.last_seen } else { $null }

            try {
                $existing = Invoke-ImperionDbQuery -Connection $Connection -Sql $matchSql -Parameters @{
                    account_id = [string]$r.account_id
                    name       = [string]$r.name
                } | Select-Object -First 1

                if ($existing -and $existing.id) {
                    Invoke-ImperionDbNonQuery -Connection $Connection -Sql $fillSql -Parameters @{
                        id           = [string]$existing.id
                        model        = $r.model
                        status       = $r.status
                        last_seen_at = $lastSeen
                    } | Out-Null
                    $updated++
                }
                else {
                    Invoke-ImperionDbNonQuery -Connection $Connection -Sql $insertSql -Parameters @{
                        account_id   = [string]$r.account_id
                        name         = [string]$r.name
                        model        = $r.model
                        status       = $r.status
                        last_seen_at = $lastSeen
                    } | Out-Null
                    $created++
                }
            }
            catch {
                # One bad row never blocks the rest: log and continue; the next run retries.
                $failed++
                Write-ImperionLog -Level Error -Source 'unifi' `
                    -Message "UniFi merge failed for device $($r.external_id) - skipped." `
                    -Data @{ external_id = $r.external_id; error = $_.Exception.Message }
            }
        }

        Write-ImperionLog -Level Metric -Source 'unifi' -Message 'UniFi merge complete.' -Data @{
            devices  = @($rows).Count
            created  = $created
            updated  = $updated
            unmapped = $unmapped
            failed   = $failed
            seconds  = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
        return [pscustomobject]@{ devices = @($rows).Count; created = $created; updated = $updated; unmapped = $unmapped; failed = $failed }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
