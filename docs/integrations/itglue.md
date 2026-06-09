# Integration — IT Glue (hub + full export)

IT Glue plays **two roles** (ADR-0006):
1. **Documentation + relationship hub** — the flatten step writes flexible assets and
   relates them to other IT Glue objects (the write path, scoped + gated).
2. **A full source export** — the entire IT Glue dataset is exported into Postgres **with
   relationships** (the read path).

## Auth
- REST API base `https://api.itglue.com` (or your region's base).
- Header `x-api-key: <key>` — the **IT Glue API key from the SecretStore**.
- **Read-only key for the export; a scoped writer key for the hub** (separate keys
  recommended so the export can never mutate).

## API shape (JSON:API)
Records are `{ "data": [ { "id", "type", "attributes": {...}, "relationships": {...} } ] }`.
- **Pagination:** `page[size]` (max 1000) + `page[number]`; follow `links.next`.
- **Filtering/sorting:** `filter[...]`, `sort`, `sort=-updated-at` for change windows.

## Resource types exported
`organizations` · `configurations` · `configuration_interfaces` · `contacts` ·
`locations` · `flexible_asset_types` · `flexible_assets` · `documents` · `domains` ·
`configuration_types` · `manufacturers` · `models` · `operating_systems` ·
`organization_types` · `organization_statuses`.
**Excluded by default:** `passwords` and any secret-bearing fields (security — ADR-0006).

## Flatten
Each record → a `[PSCustomObject]` of `id` + the `attributes` we care about + `organization-id`
(from relationships). Lossless `raw_payload` retained in bronze.

## Relationships → Postgres
IT Glue relationships are open/typed. Rather than a column per relation, capture them in one
**polymorphic many-to-many edge table** plus per-type tables — see
[../database/itglue-to-postgres-relationships.md](../database/itglue-to-postgres-relationships.md).

## Change detection
`sort=-updated-at` + the bronze `content_hash` per record. Pull only pages newer than the
last successful watermark; within a page, skip records whose hash is unchanged.

## Flexible-asset write path (hub)
- Ensure a Flexible Asset Type exists (`GET/POST /flexible_asset_types`), idempotent by name.
- Create/update flexible assets (`POST/PATCH /flexible_assets`) with traits; relationships
  via **Tag** traits referencing Organizations / Configurations / other Flexible Assets.

## Rate limits & retry
IT Glue enforces request-rate caps (per-key, per-10s and daily). Honor `429`/`Retry-After`,
backoff, and keep `page[size]` high to minimize calls. Log counts + duration + rate headers.

## Assumptions to confirm on first live run
- Regional API base URL and exact rate caps for the plan.
- Which resource types are licensed/enabled in the tenant.
- Trait schema for each Flexible Asset Type the hub writes.
