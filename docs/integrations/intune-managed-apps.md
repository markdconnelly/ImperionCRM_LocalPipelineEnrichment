# Integration — Intune managed apps (Graph deviceAppManagement)

**Purpose.** Land the Intune managed-app inventory in bronze so the app estate is drillable
on the device/asset detail (issue #143; front-end ImperionCRM #261; Mark's 2026-06-12
per-source review). Intune devices (`Get-ImperionM365Device`), compliance and device
configuration (front-end 0069/0038, ADR-0047/0051) already exist — managed apps were the
remaining gap in the drillable Intune asset picture.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post | Bronze table (frontend ImperionCRM #261) | Source |
| --- | --- | --- | --- | --- |
| Managed apps | `Get-ImperionIntuneManagedApp` | `Set-ImperionIntuneManagedAppToBronze` | `intune_managed_apps` | `m365` |

One Graph call per tenant lists the whole app estate (`/deviceAppManagement/mobileApps`).
Standard envelope, PK `(tenant_id, source, external_id)` with `external_id` = the **Graph
mobileApp id**, change-detected upsert via the issue-#105 scaffold with the proposed-#261
`-ColumnSet` projection (future collector fields drop from the flat projection but survive
in `raw_payload`). Flat columns are all-text per the bronze contract — booleans land
`'true'`/`'false'`, dates ISO 8601.

`app_type` flattens the Graph `@odata.type` discriminator (e.g. `win32LobApp`,
`officeSuiteApp`, `webApp`) with the `#microsoft.graph.` namespace trimmed, so the drill-in
can group by archetype without re-parsing the payload. The `largeIcon` base64 blob is
deliberately NOT lifted to a flat column (row bloat, no query value) — it stays in
`raw_payload`.

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`,
ADR-0002 cert custody; per-client app model per pipeline ADR-0018), single-tenant against
the Imperion company tenant by default; fan-out via `IMPERION_M365_TENANT_IDS`.
Application permission **DeviceManagementApps.Read.All** — read-only; a **new grant** on
the Onboarding app (admin consent required before LIVE). Customer tenants read via GDAP (§3).

## Endpoints, paging, rate limits
- `GET /v1.0/deviceAppManagement/mobileApps`; paging follows `@odata.nextLink`
  (`Invoke-ImperionGraphRequest`); 429/Retry-After handled by the shared retry core. One
  collection call per tenant — well inside Graph's Intune throttling budget at the daily
  cadence.
- Bronze over-collects: full app record lossless in `raw_payload`; flat columns are the
  queryable subset (publishing state, featured/assigned flags, publisher, version, owner,
  developer, dependency/supersedence counts, created/last-modified timestamps).

## Cadence & gates (scheduled-tasks/README.md)
`m365/intune-apps` **daily** (app inventory is slow-changing). Gates (fail soft — the
task's catch logs Warn + exits clean):
1. **DeviceManagementApps.Read.All grant** — new read scope; until admin-consented on the
   Onboarding app the Graph call 403s and the task gates.
2. **Front-end migration (ImperionCRM #261) prod apply** — until `intune_managed_apps`
   exists with the `imperion-localpipeline` grants, the upsert fails loudly and the task
   gates. No local-pipeline change needed after apply.
3. Task **registration** itself is deferred to server bringup (#102).

## Provenance & PII posture
Rows are stamped source/collected_at per the envelope. Managed-app inventory is operational
configuration, not personal data — but per-tenant isolation is absolute (`tenant_id` on
every row, no cross-tenant reads) and runs log counts/durations only, never row content.
Feeds the security/asset view on the company asset, never outreach.
