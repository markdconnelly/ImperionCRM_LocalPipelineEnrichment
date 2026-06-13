# Integration — SharePoint site inventory (Graph /sites, NO file content)

**Purpose.** Land a detailed, drillable inventory of every SharePoint site per client in
bronze (issue #137; front-end migration 0078 / issue #255 / front-end PR #286; Mark's
2026-06-12 per-source verdict). Domain was entirely absent before this — no other bronze
covers SharePoint. **Site METADATA only, by hard rule:** `Files.Read.All` was pruned from
the Onboarding app the same day; `Sites.Read.All` is retained. This collector makes **no
calls to `/drives`, `/drive`, `/items`, or any content endpoint, ever** — the one Graph
call is the `/sites/getAllSites` enumeration, and migration 0078 structurally has no
file/drive/item columns to land such data in. Any future file-level need is a new Mark
verdict + permission grant + migration, not a tweak here.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post | Bronze table (frontend migration 0078) | Source |
| --- | --- | --- | --- | --- |
| Sites | `Get-ImperionSharePointSite` | `Set-ImperionSharePointSiteToBronze` | `sharepoint_sites` | `m365` |

One Graph enumeration per tenant covers every site, personal (OneDrive) sites included
and flagged via `is_personal_site`. Standard envelope, PK
`(tenant_id, source, external_id)` with `external_id` = the **Graph composite site id**
(`hostname,siteCollectionId,webId`), change-detected upsert via the issue-#105 scaffold
with the exact-0078 `-ColumnSet` projection (future collector fields drop from the flat
projection but survive in `raw_payload`). Flat columns are all-text per the bronze
contract — the boolean lands `'true'`/`'false'`, dates re-serialize ISO 8601.
`storage_used_bytes` / `storage_quota_bytes` map **only where Graph exposes them on the
site object itself** — typically NULL today (storage truth lives on the drive resource,
which this collector is forbidden to call).

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`,
ADR-0002 cert custody; per-client Onboarding app model per pipeline ADR-0018 amendment),
single-tenant against the Imperion company tenant by default; fan-out via
`IMPERION_M365_TENANT_IDS`. Application permission **Sites.Read.All** — already
admin-consented on the Onboarding app; read-only, no new write grant.
**Files.Read.All is pruned and must stay pruned for this feed.**

## Endpoints, paging, rate limits
- `GET /v1.0/sites/getAllSites` — the application-permission site enumeration; paging
  follows `@odata.nextLink` (`Invoke-ImperionGraphRequest`); 429/Retry-After handled by
  the shared retry core. One collection enumeration per tenant — trivially inside
  Graph's SharePoint throttling budget at the daily cadence.
- Bronze over-collects: full site record lossless in `raw_payload` (incl. `siteCollection`
  / `sharepointIds` facets); flat columns are the queryable subset (display name, name,
  web URL, description, created/modified, template, personal-site flag, site-collection
  hostname, storage metrics where present).

## Cadence & gates (scheduled-tasks/README.md)
`m365/sharepoint-sites` **daily** (site inventory is slow-changing). Gates (fail soft —
the task's catch logs Warn + exits clean):
1. **Migration 0078 prod apply** — until `sharepoint_sites` exists with the
   `imperion-localpipeline` grants, the upsert fails loudly and the task gates. No
   local-pipeline change needed after apply.
2. Task **registration** itself is deferred to server bringup (#102).

## Provenance & PII posture
Rows are stamped source/collected_at per the envelope. Site names, URLs, and descriptions
are client business metadata (personal sites embed a user's name in the URL) — never log
row content (counts/durations only); data feeds the drillable sites section on the
account-scoped Company 360 (front-end PR #286), never outreach. **No file or document
content is collected, stored, or transmitted by this integration.**
