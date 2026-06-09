# Change detection — "check for updates; if nothing changed, move on"

Every job is idempotent and cheap to re-run. The mechanism is a **content hash** per record
plus a **per-(source,type) watermark**.

## Content hash
- After flattening, compute a stable hash over the **meaningful attributes only** (exclude
  volatile fields like `collected_at`, ETags, and server-side `lastSeen` timestamps that
  change without a real change). Helper: `Get-ImperionContentHash` (SHA-256 over canonical
  JSON of the selected fields).
- Compare to the last `content_hash` stored in the bronze row for that
  `(tenant_id, source, external_id)`.
  - **Unchanged →** skip the IT Glue write **and** the Postgres upsert; log `unchanged`.
  - **Changed / new →** write IT Glue + upsert bronze; log `created`/`updated`.

## Watermark (incremental pulls)
- Where the source supports it, pull only deltas: IT Glue `sort=-updated-at`, Autotask
  `lastModifiedDateTime`/`lastActivityDate`, Graph `$filter` on change tracking.
- Persist the max processed `updated-at` per `(source, type)` so the next run starts there.
- First run / no watermark → full pull.

## Where state lives
- **Primary:** the bronze `content_hash` column (the DB is the system of record).
- **Watermarks:** a small `pipeline_watermark(source, type, last_updated_at, last_run_at)`
  table (proposed in `/sql`) or a local JSON cache under `config/state/` if the DB table
  isn't yet migrated.

## Logging
Each run logs per source: scanned, unchanged, created, updated, errors, duration. This makes
"nothing changed, moved on" auditable.
