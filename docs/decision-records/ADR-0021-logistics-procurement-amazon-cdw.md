# ADR-0021: Logistics / procurement — Amazon Business + CDW read-only orders pull into bronze

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-15 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0001; ADR-0005; ADR-0006; ADR-0018; ADR-0019; ADR-0020; frontend ADR-0042; frontend ADR-0017 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as the placeholder
> `ADR-0021`; the orchestrator confirms/renames this file to the next free local-pipeline ADR
> number (next free after 0020) at merge and fixes every reference + the index row. **Do not
> reserve a number now.** The `_template.md` placeholder `ADR-NNNN` is untouched.

> **Scope: ADR + collectors ship TOGETHER in this PR.** Unlike ADR-0018 / 0019 / 0020 (ADR
> phase a wave ahead of the gated collectors), the front-end logistics-bronze migration `0120`
> is **already merged + prod-applied + verified** (`amazon_business_orders`, `cdw_orders`), so
> the design **and** the collectors land in one PR. This repo never creates tables (§5/§6,
> ADR-0005) — it **fails loudly** on a missing one. The collectors are DORMANT until the new
> SecretStore credentials are provisioned (Mark).

## Problem

The MSP buys hardware and supplies through two procurement channels — **Amazon Business** and
**CDW** — and the orchestrator / BI engine (§1, "coverage is the goal; gaps are bugs") sees
**none** of it. What was ordered, what it cost (spend), where the shipment is (tracking), and when
it lands are first-class operational + BI signals: procurement spend feeds account/device-supply
health, and in-flight shipments answer "where is the laptop for the new hire." Epic #194 splits the
source-catalog expansion **by domain**; this is the **logistics / procurement** domain (child D,
#198). We need a **read-only** pull of orders + shipment/tracking + spend lines from both channels
into bronze.

## Context

- **Schema is front-end-owned (system CLAUDE.md §1, ADR-0005, frontend ADR-0017).** The physical
  bronze tables `amazon_business_orders` / `cdw_orders` are defined by **front-end migration `0120`**
  (frontend #688) — a **lossless envelope** (flat curated columns + lossless `raw_payload jsonb`,
  PK `(tenant_id, source, external_id)`). They are **already merged + prod-applied + verified**, so
  the collectors build now. This repo is a **producer only**: it writes the migration-defined tables
  and **fails loudly** if one is absent (ADR-0005 §4). **No DDL is defined in this ADR.**
- **Two new sources, two new connections, two new COMPANY credentials.** Neither source is wired
  yet. Each gets a connect-layer helper (`Invoke-ImperionAmazonBusinessRequest` /
  `Invoke-ImperionCdwRequest`) and a SecretStore-first / Key-Vault-fallback credential resolver
  (`Resolve-ImperionAmazonBusinessToken` / `Resolve-ImperionCdwApiKey`), mirroring the EasyDMARC /
  Datto pattern exactly. Both credentials are **Imperion's own purchasing accounts**, not per-client
  keys.
- **A home server behind NAT cannot receive procurement webhooks (ADR-0001 / frontend ADR-0042).**
  Both APIs are pull-only; all scheduled **bulk** ingestion belongs in this repo. Latency-sensitive
  / inbound work stays in the cloud plane.
- **Pure logistics data skips IT Glue (ADR-0006).** Procurement orders/spend are a BI signal the
  agent reasons over, not an IT Glue documented operational object, so every collector flattens
  **straight to Postgres** — the IT Glue documentation step is skipped, exactly as for the QBO
  finance sources (ADR-0020) and KQM/DocuSign.

## Options considered

1. **One ADR + collectors for the logistics domain (Amazon Business + CDW), two new read-only
   connections + COMPANY-credential resolvers, FE `0120` already applied so collectors ship in the
   same PR.** *(Chosen.)* The two sources share one domain framing (procurement → bronze → BI),
   one auth shape (bearer header, SecretStore-first resolver), one "pure-logistics →
   straight-to-Postgres" path, and one driver. Epic #194 splits by domain and this **is** the
   logistics domain.
2. One ADR/PR per source (Amazon Business, then CDW). Rejected — they ship as one domain over near-
   identical adapters; splitting strands them from their shared gating + BI rationale and doubles the
   review surface for no isolation benefit (the budget fits one micro-PR).
3. **A write-capable scope** (e.g. placing orders via the API). **Rejected** — violates §2/§8
   (read-only by default; any write is an explicit, gated grant). Read-only forever; the app never
   places or modifies an order.
4. **Route the bulk pull through the cloud `ImperionCRM_Pipeline`.** Rejected — bulk/scheduled/
   high-volume is exactly what frontend ADR-0042 / ADR-0001 move **off** Azure compute.
5. **IT Glue path for the orders** (document them as IT Glue assets). Rejected — procurement spend is
   a BI signal, not operational documentation; straight-to-Postgres (ADR-0006 §2), same call as QBO.

## Decision

**Adopt Amazon Business + CDW as read-only logistics / procurement sources into bronze, ADR +
collectors in one PR (FE `0120` already applied). Add one connect helper + one credential resolver +
one get→post collector pair per source over two new connections — read-only, no write authority,
ever. DORMANT until the new SecretStore credentials are provisioned (Mark).**

### 1. Bronze targets (FE-owned, front-end migration `0120` / frontend #688 — already applied)

The **physical table names are owned by front-end `0120`**. This ADR **references them by name**;
the collectors **fail loudly** if a table is absent (ADR-0005). Each table is the canonical lossless
envelope (`tenant_id`, `source`, `external_id` = the order id, `collected_at`, `raw_payload jsonb`,
`content_hash`) + curated flat columns; bronze over-collects every attribute (full per-line
procurement detail + carrier/tracking detail stays lossless in `raw_payload`), silver narrows.

| Source | Bronze table (front-end `0120`) | `source` value | external_id | Grain / BI meaning |
|---|---|---|---|---|
| Amazon Business | `amazon_business_orders` | `amazon_business` | order id | order + shipment/tracking + spend → procurement / device-supply BI signal |
| CDW | `cdw_orders` | `cdw` | order number | order (+ PO) + shipment/tracking + spend → procurement / device-supply BI signal |

### 2. Naming + pattern

- Source keys `amazon_business` and `cdw` (no digit-prefix rule — neither leads with a digit, §5).
- Cmdlet nouns: `Get-ImperionAmazonBusinessOrder` → `Set-ImperionAmazonBusinessOrderToBronze`, and
  `Get-ImperionCdwOrder` → `Set-ImperionCdwOrderToBronze`. Connect helpers
  `Invoke-ImperionAmazonBusinessRequest` / `Invoke-ImperionCdwRequest`; module-internal credential
  resolvers `Resolve-ImperionAmazonBusinessToken` / `Resolve-ImperionCdwApiKey`.
- One scheduled task per (source, entity) (§1): `amazonbusiness/orders.task.ps1`, `cdw/orders.task.ps1`.
- Each collector follows the canonical pattern (§6): connect-layer page/cursor-walk → flatten to a
  flat `[PSCustomObject]` table → import to bronze, **upsert idempotent on
  `(tenant_id, source, external_id)`**, **skip on unchanged `content_hash`** (never re-write
  unchanged rows). Pure logistics → **straight to Postgres, IT Glue skipped** (ADR-0006). The post
  writers are ~15-line adapters over the shared `Invoke-ImperionBronzePost` scaffold (`-ColumnSet`
  projection: a future collector field can never break the insert; extras survive in `raw_payload`).
- **Hermetic tests:** every connect helper + collector + writer ships Pester unit tests that **mock
  the HTTP boundary** (no live API call in CI) — flatten-shape assertions, paging termination,
  casing-drift tolerance, idempotent-upsert envelope, `-WhatIf` gate. `PSScriptAnalyzer` clean.

### 3. Auth — two COMPANY credentials, read-only, header-borne

Each source resolves its credential SecretStore-first / Key-Vault-fallback (mirroring EasyDMARC /
Datto) and sends it as an `Authorization: Bearer` header — **request URLs are NOT secret-bearing**.
New SecretStore secret NAMES (values provisioned by Mark; never in the repo):

| Source | SecretStore name (mirror) | Key Vault name (original) |
|---|---|---|
| Amazon Business | `amazon-business-token` | `AmazonBusiness-Token` |
| CDW | `cdw-api-key` | `CDW-API-Key` |

## Consequences

### Security impact

- **Read-only everywhere — no procurement write surface, ever.** The pull requests **only read
  scopes**; no order is placed, modified, or cancelled via the API. Any future write is an explicit,
  gated grant (§2/§8).
- **No secret values anywhere** (system CLAUDE.md §2). Only the stable secret **names**
  (`amazon-business-token` / `cdw-api-key`, KV `AmazonBusiness-Token` / `CDW-API-Key`) are
  referenced; values live in the cert/CMS-unlocked SecretStore (§2), sent as a bearer header, never a
  querystring or command line. **Never commit secrets.** A credential-resolution failure **fails
  closed** — the task logs the gap and exits cleanly, no silent retry.
- **Procurement detail → bronze, access-controlled.** Order rows carry order totals (spend), buyer
  names, and shipping detail. They land in the access-controlled shared store tagged with the owning
  **tenant** (per-tenant isolation, §3 — here the partner tenant, since these are the MSP's own
  purchasing accounts); the structured logs record **counts only — never amounts, buyer names, or
  row content** (the §8 never-log-the-fact posture).

### Cost impact

- Negligible ingest cost — low-volume daily scheduled page/cursor-walks per source; idempotent upsert
  on `(tenant_id, source, external_id)` + `content_hash` skip avoids rewriting unchanged rows; no
  embedding cost at the bronze stage.

### Operational impact

- **One gate to LIVE (BUILD is already done — `0120` is applied):** the **new SecretStore
  credentials** (`amazon-business-token` / `cdw-api-key`, or the Key Vault originals) provisioned by
  Mark, after confirming Imperion's Amazon Business + CDW plans include API access. The collectors
  are **deploy-ahead/gated**: each daily task logs + exits cleanly until its credential is reachable.
- **Scheduled tasks (registered at server bringup #102, §1 one-task-per-(source,entity)):**
  `amazonbusiness/orders`, `cdw/orders` — added to `docs/operations/scheduled-task-registry.md`,
  run-as the local service account (ADR-0012).
- **CONFIRM-BEFORE-LIVE.** The base hosts, resource paths, pagination scheme (Amazon = cursor /
  `nextToken`; CDW = `?page=N`), auth header form, and field names are modeled from public docs and
  UNVERIFIED until the credentials land; each flat column leads with the most likely name + a short
  fallback chain, misses land NULL, `raw_payload` keeps everything.
- **Front-end follow-up (OKF + silver, system CLAUDE.md §11).** This PR touches **no silver entity**
  — bronze landing tables are not silver entities (frontend `0120` says so explicitly), so **no OKF
  concept-file / coverage-matrix change is required here**. If/when a silver procurement/spend rollup
  is later modeled (procurement spend → account/device-supply health), that silver-shape /
  source-of-record decision is **proposed back to the front end** (file a front-end issue then,
  parallel to the schema-ownership rule).
- **Rotation runbook.** The two credentials follow the standard SecretStore rotation
  (`docs/operations/secret-rotation.md`): rotate the value in Key Vault, mirror to the SecretStore
  name, no code change. Integration detail in `docs/integrations/logistics-procurement.md`.

## Future considerations

- **Confirm live shapes before LIVE** (the EasyDMARC #122 / Datto #195 precedent): the production
  base hosts, the orders resource paths, the pagination schemes, the auth header form, the order +
  shipment + per-line field names — all modeled from public docs but UNVERIFIED until the credentials
  land.
- **Per-line procurement detail → silver.** The lossless `raw_payload` keeps each order's line items
  (SKU/ASIN, qty, unit price). A later silver model could explode lines into a procurement-line
  entity for SKU-level spend BI — a follow-up once bronze is flowing.
- **Logistics → silver → gold / embeddings.** Once procurement bronze lands, a silver spend/shipment
  rollup feeding account/device-supply health, then a gold knowledge object the orchestrator can
  reason over (§7) — a follow-up once bronze + silver are flowing.
- **More procurement channels.** Other vendors (Dell, Ingram, distributor portals) would follow the
  same connect/resolver/get/post shape — a versioned extension, not this slice.

## Cross-references

ADR-0001 (cloud keeps webhooks; local owns scheduled bulk) · ADR-0005 (source catalog & table
naming; fail-loud-on-missing-table) · ADR-0006 (IT Glue hub — **skipped** for pure logistics) ·
ADR-0018 / ADR-0019 (the W28/W29 LP managed-estate / security domains — the SecretStore-first
resolver + gated-collector pattern this ADR mirrors; here the FE migration is already applied so
ADR + collectors ship together) · ADR-0020 (the sibling finance domain of epic #194 — same
straight-to-Postgres, read-only, one-task-per-entity framing) · frontend ADR-0042 (four-repo split —
bulk off Azure compute) · frontend ADR-0017 (schema ownership — migrations are front-end-owned;
`0120` defines `amazon_business_orders` / `cdw_orders`). Issues: **#194** (epic — source-catalog
expansion, split by domain), **#198** (this child — **logistics / procurement: Amazon Business +
CDW; ADR + collectors ship together; CLOSES at merge**), **frontend #688** (bronze-batch-B migration
`0120`), **#197** (sibling finance domain), **#195** / **#196** (sibling managed-estate / security
domains).
