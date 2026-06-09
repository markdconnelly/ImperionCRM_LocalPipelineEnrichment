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
