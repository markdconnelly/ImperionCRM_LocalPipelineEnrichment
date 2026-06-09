# Medallion flow & write path

This repo produces bronze/silver/gold rows + vectors into the shared PostgreSQL + pgvector
DB. It **never owns migrations** (front-end ADR-0017); it reads the ERD as a contract.

## The flat-table spine
Every source pull flattens to a `[PSCustomObject]` table carrying the same envelope:

| Column | Meaning |
| --- | --- |
| `tenant_id` | owning customer tenant (per-tenant isolation, absolute) |
| `source` | logical source key (`m365`, `autotask`, `itglue`, `apollo`, `kqm`, `docusign`, `website`, `azure`, `sentinel`) |
| `external_id` | stable id in the source |
| `content_hash` | hash of the meaningful attributes (change detection) |
| `collected_at` | pull timestamp |
| `raw_payload` | lossless original (jsonb) |

## Layers
- **Bronze** — the flat table imported as-is; one physical table per `(source, entity)`
  (convention `{source}_{entity}`, ADR-0005). Upsert on `(tenant_id, source, external_id)`.
- **Silver** — unified `contact` / `account` / `device` / `proposal` / `contract` /
  `ticket`, recomputed by **precedence** with manual `website_*` highest (front-end
  ADR-0039 / pipeline ADR-0009).
- **Gold** — summaries + knowledge objects across **CRM and support**, feeding the agent.

## Idempotency (mandatory)
A re-run converges, never duplicates. Unchanged `content_hash` → no write, no re-embed.

## DB access
Short-lived Entra token (ADR-0003), TLS, table-scoped role. Bulk loads use set-based
upserts (`COPY` → temp → `INSERT … ON CONFLICT DO UPDATE`).

## Coverage goal
Capture **all** company data so the front-end agents are aware of everything (CLAUDE.md §1).
Built as **many small jobs** (one per source+entity), not a monolith.
