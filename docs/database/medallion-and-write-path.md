# Medallion flow & write path

This repo produces bronze/silver/gold rows + vectors into the shared PostgreSQL + pgvector
DB. It **never owns migrations** (front-end ADR-0017); it reads the ERD as a contract.

> **The medallion flow *is* memory consolidation.** In Imperion OS (data-as-kernel +
> second-brain-as-OS) this write path is the **hippocampus** turning perception into durable
> long-term memory: **bronze = raw experience** (lossless capture), **silver = facts**
> (refined, deduped, precedence-merged), **gold = knowledge** (composed, agent-ready), and
> **vectors = the encoding for recall**. The "capture all the data" coverage goal below is the
> second-brain thesis; the consolidated memory it produces is **identity-scoped** (canon /
> company / personal, behind the RLS access spine). Full argument:
> [`data-design-for-agents.md`](https://github.com/markdconnelly/ImperionCRM/blob/main/docs/architecture/data-design-for-agents.md)
> (front-end canonical, linked not duplicated).

## The flat-table spine
Every source pull flattens to a `[PSCustomObject]` table carrying the same envelope:

| Column | Meaning |
| --- | --- |
| `tenant_id` | owning customer tenant (per-tenant isolation, absolute) |
| `source` | logical source key (`m365`, `autotask`, `itglue`, `apollo`, `kqm`, `docusign`, `website`, `azure`, `sentinel`, `defender`, `facebook`, `instagram`, `meta`) |
| `external_id` | stable id in the source |
| `content_hash` | hash of the meaningful attributes (change detection) |
| `collected_at` | pull timestamp |
| `raw_payload` | lossless original (jsonb) |

## Layers
- **Bronze** — the flat table imported as-is; one physical table per `(source, entity)`
  (convention `{source}_{entity}`, ADR-0005). Upsert on `(tenant_id, source, external_id)`.
- **Silver** — unified `contact` / `account` / `device` / `proposal` / `contract` /
  `ticket`, recomputed by **precedence** with manual `website_*` highest (front-end
  ADR-0039 / pipeline ADR-0009). **Device-merge precedence (ADR-0018 §2):**
  `website > datto_rmm > m365 > itglue` — Datto RMM is a strong machine device authority
  (device-existence + live-state) above `m365`/`itglue` but below the `website`
  resurrection guard; Datto BCDR contributes **backup-posture fields** to the same
  `device` (field-scoped merge, joining on `device_uid`), not device-identity precedence.
  This particular **`device` silver merge stays cloud-Pipeline owned** — it is part of the
  live/webhook + `website_*`-fed contact/account/device sweep, which remains in the cloud under
  **ADR-0026** (a NAT'd home server can't receive the signed webhooks that trigger it). The
  on-prem collectors only write the Datto/m365/IT Glue bronze; the precedence + BCDR field-merge
  are proposed back to the front-end OKF `device` concept + `coverage-matrix.md` at merge (system
  CLAUDE.md §11).
  > **But not all silver merge is cloud-owned.** Under ADR-0026 ("merge co-locates with
  > ingestion"), this repo owns the bronze→silver merge for the sources it *bulk-ingests* —
  > posture, Meta, DNS, M365 directory groups (#239), and Azure ARM `cloud_asset` (#241) — via
  > idempotent `Invoke-Imperion*Merge` cmdlets. Only the webhook/`website_*`-fed sweep
  > (contact/account/device/contract/ticket/opportunity/expense + DocuSign) stays in the cloud.
- **Gold** — summaries + knowledge objects across **CRM and support**, feeding the agent.

## The post-writer scaffold (one deep module)
Every `Set-Imperion*ToBronze` post-layer writer is a thin adapter over the module-internal
`Invoke-ImperionBronzePost` (issue #105): the adapter collects pipeline rows and declares
**table + envelope shape + log source**; the scaffold owns the empty-input zero tally, the
delegated `ShouldProcess` gate, the own-vs-reuse connection lifecycle (ADR-0003), the
`Invoke-ImperionBronzeUpsert` call, and the metric log line. Three envelope shapes:
- **Standard envelope** (default) — rows pass through as-is; change-detected upsert on
  `(tenant_id, source, external_id)`.
- **Per-source shape** (`-PerSourceShape`, front-end ADR-0039 tables) — rows project to
  `{ external_ref ← external_id, payload_bronze ← raw_payload }`, upsert on `external_ref`
  with `-NoChangeDetect` (no `content_hash` column; the merge resolves change).
- **Column-set projection** (`-ColumnSet`, over-collecting collectors) — rows project to
  exactly the migration-defined column set; extras survive only in `raw_payload`. Before
  the upsert, the declared set is validated against the live table's
  `information_schema.columns` (`Assert-ImperionColumnSet`, #427): a declared column the
  table doesn't have fails fast with an error naming the table + the missing columns, so
  schema drift never surfaces as an opaque insert failure (CLAUDE.md §6 "fail loudly").

New collectors add a ~15-line adapter, never a new copy of the scaffold.

The one structural exception is the multi-table router `Invoke-ImperionITGlueExportToBronze`:
it keeps its own batch-level `ShouldProcess` gate, entity routing, and connection lifecycle,
and calls the scaffold per routed table in **ungated router mode** (no `-CallerCmdlet` — the
batch is already gated) for the upsert + metric log.

## Idempotency (mandatory)
A re-run converges, never duplicates. Unchanged `content_hash` → no write, no re-embed.

## DB access
Short-lived Entra token (ADR-0003), TLS, table-scoped role. Bulk loads use set-based
upserts (`COPY` → temp → `INSERT … ON CONFLICT DO UPDATE`).

## Coverage goal
Capture **all** company data so the front-end agents are aware of everything (CLAUDE.md §1).
Built as **many small jobs** (one per source+entity), not a monolith.
