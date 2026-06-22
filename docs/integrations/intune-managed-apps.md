# Integration — Intune managed apps (Graph deviceManagement detectedApps)

**Purpose.** Land the **per-device** Intune app inventory in bronze so the installed-app estate
is drillable on the device/asset detail (issue #252; front-end ImperionCRM #261 / migration
**0148**; Mark's 2026-06-12 per-source review). Intune devices (`Get-ImperionM365Device`),
compliance and device configuration (front-end 0069/0038, ADR-0047/0051) already exist — the
per-device managed-app inventory was the remaining gap in the drillable Intune asset picture.

> **Schema reconcile (#252).** The first cut (#143) collected the tenant-level `mobileApps`
> *catalog*; the schema that actually landed (migration 0148) is the **per-device** app
> inventory the device-CI detail drills into. This collector was reconciled to that shape —
> one bronze row per **(device, app)**, keyed for the device join.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post | Bronze table (frontend migration 0148) | Source |
| --- | --- | --- | --- | --- |
| Per-device apps | `Get-ImperionIntuneManagedApp` | `Set-ImperionIntuneManagedAppToBronze` | `intune_managed_apps` | `m365` |

For each tenant the collector pages `/deviceManagement/managedDevices` (the join anchor), then
for each device pages `/deviceManagement/managedDevices/{id}/detectedApps`, emitting one flat row
per (device, app). Standard envelope, PK `(tenant_id, source, external_id)` with `external_id` =
**managed_device_id + app_id**, change-detected upsert via the issue-#105 scaffold with the 0148
`-ColumnSet` projection (future collector fields drop from the flat projection but survive in
`raw_payload`). Flat columns are all-text per the bronze contract — numbers/dates stringified.

**Drill join.** `managed_device_id` (= `intune_managed_devices.external_id`, the primary key) and
`serial_number` (fallback) mirror the silver `device` merge keys the device CI already laterals
`intune_managed_devices` on; `device_name` is denormalised for display. Both join keys are indexed
by 0148.

**`app_type` provenance.** Stamped `'detected'` for this feed (the detected-inventory half). The
0148 column also admits `'managed'` for a future assigned-app install-status feed into the same
table; `install_state` / `install_state_detail` populate only from that feed and land NULL here.

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`, ADR-0002 cert
custody; per-client onboarding-app model, §3 / pipeline ADR-0018), single-tenant against the
Imperion company tenant by default; fan-out via `IMPERION_M365_TENANT_IDS`. Application permission
**DeviceManagementApps.Read.All** — read-only; a **new grant** on the Onboarding app (**admin
consent required before LIVE — Mark-gated ops**). Client tenants read via the per-client
onboarding app (§3).

## Endpoints, paging, rate limits
- `GET /v1.0/deviceManagement/managedDevices` (`$select=id,deviceName,serialNumber`) for the join
  anchor, then `GET /v1.0/deviceManagement/managedDevices/{id}/detectedApps` per device. Paging
  follows `@odata.nextLink` (`Invoke-ImperionGraphRequest`); 429/Retry-After handled by the shared
  retry core. **N+1 call shape** (one per device) — inherent to the per-device endpoint; fine at
  the daily cadence, watch the Intune throttling budget for very large estates.
- **CONFIRM-BEFORE-LIVE:** the detected-app flat columns map the Graph `detectedApp` fields
  (`displayName`/`version`/`publisher`/`platform`/`sizeInByte`). Fields a `detectedApp` does not
  expose land NULL and stay lossless in `raw_payload` — verify the live shape on the first real
  pull. Bronze over-collects: the full app record is lossless in `raw_payload`.

## Cadence & gates (scheduled-tasks/README.md)
`Imperion-IntuneApps` (`Invoke-ImperionIntuneAppSync`) **daily** (app inventory is slow-changing),
already registered (no bring-up registration step left). Gates (fail soft — per-tenant failure is
isolated by `Invoke-ImperionM365EstateSweep`; the writer fails loud only on a missing table/grant):
1. **DeviceManagementApps.Read.All grant** — new read scope; until admin-consented on the
   Onboarding app the Graph call 403s and the run yields nothing. **This is the only remaining gate.**
2. **Front-end migration 0148** — **APPLIED to prod** (`intune_managed_apps` exists with the
   `imperion-localpipeline` write grant), so the upsert path is ready.
3. Host run is operator-driven on the on-prem server (#102).

## Provenance & PII posture
Rows are stamped source/collected_at per the envelope. Per-device app inventory is operational
configuration, not personal data — but per-tenant isolation is absolute (`tenant_id` on every row,
no cross-tenant reads) and runs log counts/durations only, never row content. Feeds the
security/asset view on the company asset, never outreach.
