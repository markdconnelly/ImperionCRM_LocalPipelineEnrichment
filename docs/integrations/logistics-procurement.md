# Integration — Logistics / procurement: Amazon Business + CDW order ingestion

**Purpose.** Imperion procures hardware and supplies through two channels — **Amazon Business**
and **CDW**. This source ingests **orders + shipment/tracking + spend lines** from both into
**bronze**, so procurement spend and in-flight shipments become first-class BI signals the
orchestrator can reason over (system CLAUDE.md §1 — "coverage is the goal; gaps are bugs"). It is
**procurement/BI data, not operational documentation**, so each collector flattens **straight to
Postgres** and **skips the IT Glue hub** (ADR-0006, same call as the QBO finance sources / KQM /
DocuSign).

> **Status: collector CODE shipped, live ingestion GATED (issue #198, ADR-0021).** The collectors
> are dormant until the new SecretStore credentials are provisioned (Mark-gated — confirm
> Imperion's Amazon Business + CDW plans include API access). The bronze tables
> `amazon_business_orders` / `cdw_orders` are owned by the **front-end repo** (system CLAUDE.md §1,
> front-end migration **0120** / #688) and are **already merged + prod-applied + verified**, so the
> collectors ship in the same PR as the ADR (no migration is added in this repo). Each daily task
> logs the gap and exits cleanly until its credential is reachable; if a table were ever absent the
> post writer **fails loudly** (ADR-0005).

## Sources & auth
| Source | API | Auth |
| --- | --- | --- |
| Amazon Business | read-only REST/OAuth `https://na.business-api.amazon.com` (placeholder — confirm) | access token sent as **`Authorization: Bearer <token>`** — SecretStore `amazon-business-token` (mirror), else Key Vault `AmazonBusiness-Token` (original, kv-imperioncrm-prd) via the cert SP |
| CDW | read-only REST `https://api.cdw.com` (placeholder — confirm) | API key sent as **`Authorization: Bearer <apiKey>`** — SecretStore `cdw-api-key` (mirror), else Key Vault `CDW-API-Key` (original, kv-imperioncrm-prd) via the cert SP |

- **COMPANY credentials, not per-client.** Both are Imperion's own purchasing accounts; every row
  is stamped the partner tenant (per-tenant isolation, §3).
- **Header auth → URLs are NOT secret-bearing** (unlike KQM's `?apikey=`). No URL redaction needed.
- **Read-only / pull-only** — no webhooks surfaced, so the scheduled bulk poll belongs **here** per
  the cloud/local boundary (CLAUDE.md §1, ADR-0001). **No write authority is requested or granted —
  no order is ever placed, modified, or cancelled.**
- **Paging:** Amazon Business walks an opaque `nextToken`/cursor; CDW walks `?page=N` from 1 (stops
  on a short page or a reported `meta.last_page`). The connect layer hard-caps pages. **Confirm both
  schemes on the first live pull.**
- **Rate limits:** per-credential, no figures published — verify on first live pull. One daily
  page-walk of the order list is well inside any plausible budget.

## Entities & Postgres targets (bronze)
| Source | Bronze table (front-end 0120) | `source` | external_id |
| --- | --- | --- | --- |
| Amazon Business order | `amazon_business_orders` | `amazon_business` | order id |
| CDW order | `cdw_orders` | `cdw` | order number |

Both tables are the **lossless envelope** (front-end `0120`): curated flat columns + lossless
`raw_payload jsonb`, PK `(tenant_id, source, external_id)`.

- `amazon_business_orders` curated columns: `order_id, order_date, order_status, order_total,
  currency, buyer_name, tracking_number, carrier, ship_status, estimated_delivery` + the envelope.
- `cdw_orders` curated columns: `order_id, po_number, order_date, order_status, order_total,
  currency, account_ref, tracking_number, carrier, ship_status, estimated_delivery` + the envelope.

**Per-line procurement detail** (items, SKU/ASIN, qty, unit price) and the **full carrier/tracking
detail** stay lossless in `raw_payload`; the flat columns are the curated, server-queryable subset
(order header + spend + a single primary tracking).

## Flatten
Standard pattern: flatten each order to `[PSCustomObject]` with the attributes we care about + the
envelope. `Get-ImperionAmazonBusinessOrder` / `Get-ImperionCdwOrder` lead each flat column with the
most likely source name and keep a short fallback chain (casing/snake-case + nested-path drift
tolerated); misses land NULL, `raw_payload` keeps everything. The post writers
(`Set-Imperion…OrderToBronze`) project to exactly the table's column set (extras dropped from the
flat projection, survive in `raw_payload`) and upsert idempotent on `(tenant_id, source,
external_id)` with content-hash skip.

## Cadence
Daily. See [`../../scheduled-tasks/`](../../scheduled-tasks) — `amazonbusiness/orders`, `cdw/orders`.

## Provenance
Order rows are stamped `source` / `collected_at` per the system provenance guardrail (CLAUDE.md §8).
Order totals (spend) and buyer names are procurement detail — the structured logs record **counts
only**, never amounts, buyer names, or row content. No client PII is collected (these are the MSP's
own purchasing accounts).

## Rotation runbook
Both credentials follow the standard SecretStore rotation (`../operations/secret-rotation.md`):
rotate the value in Key Vault (`AmazonBusiness-Token` / `CDW-API-Key`), mirror to the SecretStore
name (`amazon-business-token` / `cdw-api-key`), no code change. A rotation-induced auth failure
fails closed — the next daily run logs the gap and exits cleanly, then converges once the new value
is in place (idempotent upsert).

## Unknowns needing a live credential (verify-first, like EasyDMARC #122 / Datto #195)
- Exact base hosts, the orders resource paths, and the pagination schemes (cursor vs page).
- The exact order + shipment + per-line field names (the flatten maps' leading names are
  best-effort; misses land NULL).
- Rate-limit numbers per credential.
- Whether Imperion's current Amazon Business / CDW plans include API access.
