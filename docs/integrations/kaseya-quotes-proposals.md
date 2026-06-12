# Integration — Kaseya stack: quotes, proposals, contracts, tickets (bulk load)

**Purpose.** Bulk-load CRM/support records from the Kaseya stack — **quotes/proposals**
(Kaseya Quote Manager, "KQM"), **contracts** and **tickets** (Autotask) — straight into
Postgres bronze. These are **pure CRM/support data**: they flatten **directly to Postgres**
and **skip the IT Glue hub** (ADR-0006).

## Sources & auth
| Source | API | Auth (secrets from SecretStore) |
| --- | --- | --- |
| KQM (Quote Manager) | Quote Manager API | API key / token |
| Autotask | REST API `https://webservicesN.autotask.net/atservicesrest/v1.0/` | `ApiIntegrationCode` + `UserName` + `Secret` headers |

## Entities & Postgres targets (bronze)
| Entity | Source(s) | Bronze table (logical) |
| --- | --- | --- |
| Proposals/Quotes | `kqm`, `website` | `kqm_proposals`, `website_proposals` |
| Contracts | `autotask`, `docusign` | `autotask_contracts`, `docusign_contracts` |
| Tickets | `autotask` | `autotask_tickets` |

(Autotask entities: `Quotes`, `Contracts`, `Tickets`. KQM: quotes/proposals.)

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
- KQM API surface and pagination (`kqm_proposals` columns).
- DocuSign contract retrieval path (envelopes API) and what counts as a "contract" record.
