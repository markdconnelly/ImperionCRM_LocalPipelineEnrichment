# Integration — Kaseya stack: quotes/opportunities, contracts, tickets (bulk load)

**Purpose.** Bulk-load CRM/support records from the Kaseya stack — **quotes**
(Kaseya Quote Manager, "KQM") as a bronze source of the **opportunity**, plus **contracts**
and **tickets** (Autotask) — straight into Postgres bronze. These are **pure CRM/support
data**: they flatten **directly to Postgres** and **skip the IT Glue hub** (ADR-0006).

> **KQM is an opportunity source, not a standalone proposal (front-end migration 0083,
> ADR-0080/0039).** The mis-modeled `kqm_proposals` (0038) is **dropped**. KQM quote
> headers land in `kqm_opportunities`; the three sources (KQM, Autotask, website) merge
> into the silver `opportunity`. The **header** (`Get-ImperionKqmOpportunity`, issue #160)
> and the **won-quote DETAIL** — sections/lines/sales orders (`Get-ImperionKqmOpportunityDetail`,
> issue #161) — are both built; the daily task chains header → won-detail. Detail **value**
> (Σ selected/non-optional lines, MRR vs one-off by `is_recurring`) is computed in the
> silver opportunity merge (pipeline #95), not here.

## Sources & auth
| Source | API | Auth |
| --- | --- | --- |
| KQM (Quote Manager) | read-only REST `https://api.kaseyaquotemanager.com/v1/` | API key as **`?apikey=` querystring** — SecretStore `kqm-api-key` (mirror), else Key Vault `KQM-API-Key` (original, kv-imperioncrm-prd) via the cert SP |
| Autotask | REST API `https://webservicesN.autotask.net/atservicesrest/v1.0/` | `ApiIntegrationCode` + `UserName` + `Secret` headers (SecretStore) |

### KQM — verified API facts (issue #98, 2026-06-12)
- **Read-only / pull-only** (no webhooks); docs at api.dattocommerce.com/docs.
- Endpoints confirmed in the public docs: `quote`, `salesorder`, `supplier`, `warehouse`.
- **Auth: `?apikey=` querystring → every request URL is SECRET-BEARING.** The connect
  layer (`Invoke-ImperionKqmRequest`) appends the key internally and the retry core
  redacts apikey-style parameters from all logs/errors. Never log a full KQM URL.
- **Paging:** `?page=N` from 1, max 100 results/page; the loop stops on a short page,
  hard-capped by `-MaxPages` (default 190 ≈ 19k rows).
- **Limits:** 60 calls/min and 20,000 calls/day; 429 + `Retry-After` handled by backoff.
- **Incremental:** `modifiedAfter=<url-encoded ISO timestamp>` (recommended by the docs).

### KQM — VERIFIED live shape (spike #427, 2026-06-13)
Ran `Get-ImperionKqmFieldName` + read-only probes against live KQM. Settled facts:
- **`status` is an INT enum code** (1 open / 2 sent / **3 WON** / 90 dead), not text;
  bronze keeps it as text, silver interprets 3 = won.
- **`salesOrderId` is present ⇔ status 3** — the won marker (drives the #161 detail pull).
- The header has **no `name`** (use `title`/`quoteNumber`) and **no `total`** — silver sums
  selected lines from the detail tables.
- **Autotask FKs are populated**: `autotaskOpportunityID`, `autotaskOrganizationID`,
  `autotaskQuoteID` — the sale→delivery seam (no mapping table needed).

The flat-column map in `Get-ImperionKqmOpportunity` leads with these verified names and
keeps a short fallback chain (casing drift tolerated; misses land NULL, `raw_payload` keeps
everything). `Get-ImperionKqmFieldName` remains the re-probe tool (emits field NAMES/types/
non-null tallies, **never values** — safe to paste into an issue).

## Entities & Postgres targets (bronze)
| Entity | Source(s) | Bronze table (logical) |
| --- | --- | --- |
| Opportunity (quote header) | `kqm`, `autotask`, `website` | `kqm_opportunities`, `autotask_opportunities`, `website_opportunities` (migration 0083) |
| Opportunity detail (won) | `kqm` | `kqm_opportunity_sections`, `kqm_opportunity_lines`, `kqm_sales_orders`, `kqm_sales_order_lines` (issue #161) |
| Contracts | `autotask`, `docusign` | `autotask_contracts`, `docusign_contracts` |
| Tickets | `autotask` | `autotask_tickets` |

`kqm_opportunities` columns (migration 0083): `quote_number, code, title, status,
sales_order_id, customer_id, autotask_opportunity_id, autotask_organization_id,
autotask_quote_id, contact_name, contact_email, owner_employee_id, created_date,
modified_date, expiry_date` + the standard envelope. `Invoke-ImperionKaseyaImport -Entity
Opportunities` (or the daily `scheduled-tasks/kqm/opportunities.task.ps1`) drives the pull.

### Won-quote detail (issue #161, `Get-ImperionKqmOpportunityDetail`)
The detail endpoints are **NOT server-filterable by quote** (`?quoteID=` is ignored — the
full collection comes back), so the collector pulls each full collection and **keeps only
rows belonging to a won quote** (the won quote-id set passed from the header pass), joined
client-side along:
`quoteline.quoteSectionID → quotesection.id → quotesection.quoteID → quote.id` and
`salesorderline.salesOrderID → salesorder.id → salesorder.quoteID → quote.id`.

| Endpoint | Bronze table | Key FK kept on |
| --- | --- | --- |
| `quotesection` | `kqm_opportunity_sections` | `quoteID` ∈ won quotes |
| `quoteline` | `kqm_opportunity_lines` | `quoteSectionID` ∈ won sections |
| `salesorder` | `kqm_sales_orders` | `quoteID` ∈ won quotes |
| `salesorderline` | `kqm_sales_order_lines` | `salesOrderID` ∈ won sales orders |

`modifiedAfter` is **unverified** on the line/section endpoints (#427), so the collector
defaults to a **full pull** and relies on the bronze **content-hash skip** for idempotency
(no re-bill on unchanged rows); the `-ModifiedAfter` parameter is exposed for when it's
confirmed. Won-quote volume is small, so the full read stays far inside the 60/min · 20k/day
budget. `Set-ImperionKqmOpportunityDetailToBronze` writes all four tables over one
short-lived-token connection.

## Flatten
Standard pattern: flatten to `[PSCustomObject]` with the attributes we care about +
`tenant_id`, `source`, `external_id`, `content_hash`, `collected_at`, `raw_payload`.

## Bulk-load strategy
- **Where appropriate, bulk-load** rather than row-by-row: stage the flat table and use a
  set-based upsert (e.g. `COPY` into a temp table → `INSERT … ON CONFLICT … DO UPDATE`).
- **Idempotent** on `(tenant_id, source, external_id)`; unchanged `content_hash` → skip.
- **Watermarking:** Autotask supports `lastActivityDate`/`lastModifiedDateTime` query
  filters; pull deltas, fall back to full load on first run.

## Autotask rate limits — SHARED budget with the cloud pipeline (#109)

Live threshold alert 2026-06-12 (entity Ticket); limits verified against the Autotask
developer docs ([thread limiting](https://www.autotask.net/help/developerhelp/Content/APIs/General/ThreadLimiting.htm),
[REST thresholds](https://www.autotask.net/help/developerhelp/Content/APIs/REST/General_Topics/REST_Thresholds_Limits.htm)):

- **Thread threshold: 3 concurrent threads per object endpoint per integration code.**
  Exceeding → **429** + an email alert to the API user; latency penalties from 3
  concurrent (+0.25 s/request) up to 10+ (+1 s).
- **Hourly threshold: 10,000 requests/hour per database**, with usage-based latency from
  5,000 (+0.5 s) and 7,500 (+1 s).
- **One integration code serves BOTH planes.** The cloud pipeline (webhook full-fetches,
  on-demand refresh) caps itself at **2 concurrent requests per instance**
  (`ImperionCRM_Pipeline` #54), leaving this loader **1 guaranteed thread**. Therefore:
  - **Keep this repo's Autotask calls sequential** (they are today — paged
    `Invoke-ImperionAutotaskRequest` loops). No `ForEach-Object -Parallel`,
    `Start-ThreadJob`, or runspace fan-out against Autotask without revisiting the
    budget split across both repos first.
  - Don't schedule multiple Autotask (source, entity) tasks at the same minute —
    stagger them; concurrent tasks are concurrent threads.
  - On a 429, back off honoring `Retry-After`, then resume; a converging idempotent
    re-run is the recovery path.

## Webhook boundary
Autotask **ticket** *webhooks* stay in the **cloud Pipeline** (ADR-0001) — those are
real-time, internet-facing. This repo does the **scheduled bulk poll** of tickets/contracts
/quotes (Autotask has no webhooks for quotes/contracts anyway).

## Confirmed against the live Autotask API (field-metadata endpoint)
- **Auth:** zone auto-discovered (`zoneInformation?user=`), then paged
  `/{Entity}/query?search=<json>` with `ApiIntegrationCode`/`UserName`/`Secret` headers.
- **Companies key is `companyID`** (not `accountID`) — contracts/tickets reference it.
- **Incremental fields:** Contracts → `lastModifiedDateTime`; Tickets → `lastActivityDate`;
  Companies/Contacts → `lastActivityDate`.
- Contracts (35 fields) and Tickets (75 fields) column sets are in
  `sql/kaseya_bronze_schema.sql` (the curated subset; full payload in `raw_payload`).

## Still assumptions (no live access yet)
- KQM detail endpoints (`quoteline`/`quotesection`/`salesorderline`) `modifiedAfter`
  support — verify on first detail run; until then the detail collector does a full pull +
  content-hash skip (issue #161, the conservative default already wired).
- DocuSign contract retrieval path (envelopes API) and what counts as a "contract" record.
