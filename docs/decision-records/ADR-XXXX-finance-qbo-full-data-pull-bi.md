# ADR-XXXX: Finance — QuickBooks Online read-only full-data pull into the intelligence / BI engine

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-15 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0001; ADR-0005; ADR-0006; ADR-0014; ADR-0018; ADR-0019; frontend ADR-0042; frontend ADR-0082; frontend ADR-0083; frontend ADR-0085; frontend ADR-0017 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as the placeholder
> `ADR-XXXX`; the orchestrator renames this file to the next free local-pipeline ADR number
> (next free after 0019) at merge and fixes every reference. **Do not reserve a number now.**
> The `_template.md` placeholder `ADR-NNNN` is untouched. (This matches the W28/W29 LP
> placeholder convention used by ADR-0018 / ADR-0019.)

> **Scope of this ADR is DESIGN ONLY.** The collector cmdlets are the **next wave (W32)** and are
> **gated on the front-end finance-bronze migration `0120`** (frontend #688), which is authored
> concurrently this wave and is **not merged yet**. This ADR records the design + decisions and
> **references the bronze table names by name only**; the collectors ship in the **collector phase
> of issue #197, which stays open** once `0120` merges + applies. This repo never creates tables
> (§5/§6, ADR-0005) — it **fails loudly** on a missing one.

## Problem

QuickBooks Online is already wired into this repo, but only for the **two narrow payroll/expense
slices** the time- and expense-tracking work required:

- the authoritative **payment fact** — `Purchase` rows → `qbo_purchases` (ADR-0014, re-targeted
  `BillPayment` → `Purchase` for Simple Start, #174 / frontend ADR-0085); and
- the expense **chart-of-accounts SoR** — expense `Account` rows → `qbo_expense_account` (ADR-0014
  amendment #168 / frontend ADR-0083).

But QBO is the company's **accounting system of record for the whole finance picture** — what the
MSP has invoiced, what customers have paid, what is outstanding (A/R), what the MSP owes and has
spent (A/P / procurement), the chart of accounts, and the period P&L. The orchestrator / BI engine
(§1, "coverage is the goal; gaps are bugs") today sees **none** of that beyond the two
reconciliation slices, so it cannot reason about **revenue, cash, account profitability, or
account-health-from-spend**. Finance is a first-class signal that is missing from the knowledge
base. We need a **read-only, full-data** QBO pull into bronze — not just the payment + category
legs — so finance becomes a first-class account-health / BI signal.

## Context

- **Schema is front-end-owned (system CLAUDE.md §1, ADR-0005, frontend ADR-0017).** The physical
  bronze tables are defined by **front-end migration `0120`** (frontend #688), **not here**. This
  repo is a **producer only**: it writes the migration-defined tables and **fails loudly** if one
  is absent (ADR-0005 §4). **No DDL is defined in this ADR.**
- **QBO is already integrated — one connection, this ADR widens it.** The existing read path is the
  connect-layer helper **`Invoke-ImperionQboRequest`** (the `conn-company-qbo` connection in
  read-only form): a single SQL-like `query` endpoint with `Authorization: Bearer <accessToken>`,
  paging in the query text (`STARTPOSITION/MAXRESULTS`), reading the SecretStore secrets
  `qbo-access-token` / `qbo-realm-id`. The existing readers are the **payment fact** (ADR-0014) and
  the **expense chart-of-accounts** (ADR-0014 #168). **This ADR is purely additive** — it adds read
  scopes + new bronze targets over the **same one connection**. **No second app registration. No
  write authority is granted, ever.**
- **QBO is cloud (Intuit Accounting API v3), Simple Start subscription, already in use.** Confirmed:
  the company is on **Simple Start** (no Accounts Payable — `Bill`/`BillPayment` return "Feature Not
  Supported", #174). The full pull models **only entities/reports Simple Start exposes**; the
  subscription is **NOT** upgraded.
- **A home server behind NAT cannot receive QBO webhooks (ADR-0001 / frontend ADR-0042).** All
  scheduled **bulk** QBO ingestion belongs in this repo; inbound webhooks and latency-sensitive
  reads stay in the cloud plane / backend QBO read client. This decision is the **on-prem scheduled
  bulk full pull**, the same source on a different plane.
- **Pure finance data skips IT Glue (ADR-0006).** QBO is accounting/CRM-finance data, not
  operational-config data, so every collector flattens **straight to Postgres** — the IT Glue
  documentation step is skipped, exactly as for the existing two QBO slices.

## Options considered

1. **One ADR widening QBO from "payroll/expense recon" to "full read-only finance source for BI";
   reuse the existing connection read-only, add read scopes + bronze targets; FE migration `0120`
   first; collectors as a gated W32 follow-up.** *(Chosen.)* The finance entities share one
   connection, one auth model, one "pure-finance → straight-to-Postgres" framing, and one driver
   (finance as a BI signal). Epic #194 splits **by domain**, and this **is** the finance domain.
2. One ADR/PR per finance entity (invoices / payments / customers / …). Rejected — they ship as one
   domain over one connection; splitting strands them from their shared auth, gating, and BI
   rationale and multiplies near-identical adapters.
3. **A second QBO app registration / a write-capable scope** for the full pull. **Rejected** —
   violates §2/§8 (read-only by default; any write is an explicit, gated grant) and the established
   QBO posture (ADR-0014: "the app never pays / never writes QuickBooks"). One connection, many
   readers, read-only forever. No second app reg.
4. **Let the backend cloud QBO read client do the full bulk pull.** Rejected — bulk/scheduled/
   high-volume is exactly what frontend ADR-0042 / ADR-0001 move **off** Azure compute; the cloud
   client stays for latency-sensitive on-demand reads.
5. Collectors in this ADR's PR (now). Rejected — blocked on `0120`; building against an absent table
   would only fail loudly (ADR-0005). Design now, build when the table exists (the ADR-0018 / 0014
   deploy-ahead precedent).

## Decision

**Adopt a read-only full QBO data pull into bronze as a first-class finance / BI source,
design-only this phase, gated on front-end migration `0120`. Reuse the existing `conn-company-qbo`
connection (`Invoke-ImperionQboRequest`) in read-only form, adding read scopes + new bronze targets
only — no second app reg, no write authority, ever.**

### 1. Bronze targets (FE-owned, front-end migration `0120` / frontend #688)

The **physical table names are owned by front-end `0120`**. This ADR **references them by name**;
the collectors will **fail loudly** if a table is absent (ADR-0005). It does **not** define their
DDL. Each table carries the canonical bronze envelope (`tenant_id`, `source` = `qbo`, `external_id`
= the QBO entity `Id`, `collected_at`, `raw_payload jsonb`, `content_hash`) per the bronze rule
(§5); bronze over-collects every attribute the API exposes, silver narrows.

| QBO entity / report | Bronze table (front-end `0120`) | Grain | BI / account-health meaning |
|---|---|---|---|
| `Invoice` | `qbo_invoices` | invoice | revenue billed; A/R when unpaid |
| `Payment` | `qbo_payments` | customer payment | cash received against invoices |
| `Customer` | `qbo_customers` | customer | finance-side customer master → join to silver account |
| `Estimate` | `qbo_estimates` | estimate / quote | pipeline / committed-but-unbilled |
| `Bill` *(modeled; see note)* | `qbo_bills` | vendor bill (A/P) | what the MSP owes — procurement / A/P |
| `Account` (chart of accounts) | `qbo_accounts` | account | full COA (revenue/expense/asset/liability) for classification + rollups |
| Profit & Loss report | `qbo_profit_and_loss` | report snapshot (period) | period P&L snapshot for revenue/margin BI |

- **`qbo_purchases` already exists (front-end migration `0092`, ADR-0014 #174) and is REUSED, not
  duplicated.** The Check/Expense payment fact stays exactly where it is; this ADR does not re-model
  or re-target it. Likewise the existing `qbo_expense_account` (expense-only COA, ADR-0014 #168) is
  untouched — `qbo_accounts` here is the **full** chart of accounts; the FE `0120` migration
  decides whether the expense slice is a view over `qbo_accounts` or stays a separate table (a
  front-end call, noted as an open item).
- **`Bill` / A/P on Simple Start is an OPEN ITEM (do not invent).** Simple Start has **no Accounts
  Payable**, so `Bill` may return "Feature Not Supported" (the same constraint that re-targeted the
  payment fact, #174). `qbo_bills` is modeled for completeness and for a future tier; whether it is
  populated now is **confirmed against the live company in the collector phase** (CONFIRM-BEFORE-LIVE).
  If unavailable, the A/P / procurement signal is carried by `qbo_purchases` + `qbo_accounts`
  (expense classifications) and `qbo_bills` stays dormant.
- **`qbo_profit_and_loss` is a report snapshot, not a transactional entity.** It is pulled from the
  QBO **Reports** API (`/reports/ProfitAndLoss`), stored as an immutable period snapshot
  (idempotent on `(tenant_id, source, period, content_hash)`), following the snapshot idiom of
  ADR-0011 (quarterly posture snapshots) rather than the upsert-on-`Id` entity idiom.

### 2. Coordination — one QBO connection, many readers (additive, breaks nothing)

There is exactly **one** QBO connection in this repo and it grows readers; it is never forked:

| Reader | Entity / report | Bronze table | Source ADR | Status |
|---|---|---|---|---|
| Payroll payment fact | `Purchase` | `qbo_purchases` | ADR-0014 (#174) | existing |
| Expense chart-of-accounts SoR | `Account` (Expense) | `qbo_expense_account` | ADR-0014 (#168) | existing |
| Finance / BI full pull | `Invoice`, `Payment`, `Customer`, `Estimate`, `Bill`, `Account`, P&L | the §1 tables | **this ADR** | new (W32) |

This ADR **widens QBO scope, breaks nothing.** The two existing readers keep their exact entities,
tables, secrets, and posture. The new collectors are **~15-line adapters over the existing
`Invoke-ImperionQboRequest`** (the connect helper, not a new scaffold), each reusing the same
`qbo-access-token` / `qbo-realm-id` secrets. The backend cloud QBO read client (backend #104) keeps
the **latency-sensitive on-demand** reads; this repo keeps the **scheduled bulk** pull — the
ADR-0001 / frontend ADR-0042 plane split is unchanged. QBO is **cloud (Simple Start), already in
use** — confirmed, no infra change.

### 3. Naming + pattern

- Source key `qbo` (no digit-prefix rule — it does not lead with a digit, §5). Cmdlet nouns mirror
  the existing pair: `Get-ImperionQboInvoice` → `Set-ImperionQboInvoiceToBronze`, and likewise
  `QboPayment`, `QboCustomer`, `QboEstimate`, `QboBill`, `QboAccount`, and `QboProfitAndLoss` (the
  report). One scheduled task per (source, entity) (§1) — `qbo/invoices.task.ps1`, etc.
- Each collector follows the canonical pattern (§6): `Invoke-ImperionQboRequest` page-walk → flatten
  to a flat `[PSCustomObject]` table → import to bronze, **upsert idempotent on
  `(tenant_id, source, external_id)`**, **skip on unchanged `content_hash`** (never re-write
  unchanged rows). Pure finance → **straight to Postgres, IT Glue skipped** (ADR-0006). The P&L
  report uses the snapshot variant (§1).
- **Hermetic-test expectation (collector phase):** every collector + the report pull ships Pester
  unit tests that **mock the HTTP boundary** (no live Intuit call in CI, mirroring the existing
  `Invoke-ImperionQboRequest` / `Get-ImperionQboPurchase` tests) — flatten-shape assertions, paging
  termination, fail-loud-on-missing-table, idempotent-upsert envelope. `PSScriptAnalyzer` clean.

## Consequences

### Security impact

- **Read-only everywhere — no QBO write surface, ever.** The pull reuses the existing read-only
  OAuth2 bearer path; **no write scope is requested and no write authority is granted** (the
  established QBO posture, ADR-0014: "the app never pays / never writes QuickBooks"). The only added
  scopes are **read scopes** for the new entities/reports.
- **No second app registration** — one `conn-company-qbo` connection. The access token
  (`qbo-access-token`) EXPIRES (~1h) and the refresh token rotates; a refresh failure **fails
  closed** (the task logs + exits, no silent retry), exactly as the existing collectors.
- **No secret values anywhere** (system CLAUDE.md §2). Only the stable secret **names**
  (`qbo-access-token`, `qbo-realm-id`) are referenced; values live in the cert/CMS-unlocked
  SecretStore (§2) and any keys ride headers / token-exchange bodies, never a querystring. **Never
  commit secrets.** No net-new secret is introduced.
- **Client financial PII → bronze, access-controlled.** Invoice/payment/customer/bill rows carry
  **client financial PII** (customer names, amounts, balances). They land in the access-controlled
  shared store tagged with the owning **tenant** (per-tenant isolation, §3); the structured logs
  record **counts only — never amounts, customer names, or row content** (the §8 / ADR-0014
  never-log-the-fact posture). No comp data (`pay_rate`) is read or stored here — it stays in the
  front-end finance-gated 0085 store.

### Cost impact

- Negligible ingest cost — low-volume scheduled incremental page-walks per entity (`MetaData.
  LastUpdatedTime` watermark where the entity supports it); idempotent upsert on
  `(tenant_id, source, external_id)` + `content_hash` skip avoids rewriting unchanged rows; no
  embedding cost at the bronze stage. The P&L snapshot is a single small report per period.

### Operational impact

- **Two gates to LIVE (BUILD is unblocked once `0120` lands):**
  1. **Front-end finance-bronze migration `0120` (frontend #688)** merged + applied — defines
     `qbo_invoices` / `qbo_payments` / `qbo_customers` / `qbo_estimates` / `qbo_bills` /
     `qbo_accounts` / `qbo_profit_and_loss`. Until then the collectors **fail loudly** on the
     missing tables (ADR-0005); the design stands and no table is touched.
  2. **QBO app-registration read scopes** for the new entities/reports + token custody (Mark) — the
     standing QBO blocker shared with backend #104 / the existing two slices. The collectors are
     **deploy-ahead/gated**: they log + exit until both the scopes and the migration land.
- **Collectors are the W32 collector phase of issue #197, which STAYS OPEN.** No `Closes #197` in
  the ADR PR — the ADR PR is `Refs #197`; the issue carries the collector slice.
- **Scheduled tasks (registered at the collector phase, §1 one-task-per-(source,entity)):**
  `Imperion-Qbo-Invoices`, `-Payments`, `-Customers`, `-Estimates`, `-Bills`, `-Accounts`,
  `-ProfitAndLoss` — added to `docs/operations/scheduled-task-registry.md` then, run-as the local
  service account (ADR-0012).
- **Front-end follow-up (OKF + silver, system CLAUDE.md §11).** Finance becoming a first-class
  account-health / BI signal — joining `qbo_customers` to the silver `account`, rolling revenue /
  A/R / A/P / margin into account health — is a silver-entity shape / source-of-record decision
  (QBO = SoR for the finance facts). The matching OKF concept file(s) + `coverage-matrix.md` row(s)
  must be **proposed back to the front end** (file a front-end issue at the collector phase, parallel
  to the schema-ownership rule). A new silver `invoice` / finance entity may warrant its own concept
  (a front-end call).
- **Integration + ops docs land in the collector-phase PR** (§9 doc standard): the existing
  `docs/integrations/quickbooks-online.md` extends with the new entities/reports (auth, exact read
  scopes, paging, fields, the P&L report params, the `Bill`/A/P CONFIRM-BEFORE-LIVE note), plus the
  scheduled-task-registry update.

## Future considerations

- **Confirm live shapes before LIVE** (CONFIRM-BEFORE-LIVE, the ADR-0014 / 0017 / 0018 precedent):
  the production base host, minor version, the `Invoice` / `Payment` / `Customer` / `Estimate`
  wrappers, and **especially whether `Bill` / A/P is available on this Simple Start company** (§1
  open item) and the exact P&L report shape — all modeled from the documented Intuit API but
  UNVERIFIED until the app registration lands.
- **`qbo_accounts` vs `qbo_expense_account`** — front-end `0120` decides whether the existing
  expense-only COA slice becomes a view over the full `qbo_accounts` or stays separate (an open
  item for the migration author; this ADR does not re-model the existing slice).
- **Finance → silver → gold / embeddings.** Once the finance bronze lands, the natural next steps are
  a silver finance rollup (revenue / A/R / A/P / margin per account) feeding account health, then a
  gold finance knowledge object the orchestrator can reason over (§7) — a follow-up once bronze +
  silver are flowing.
- **Subscription tier.** If the MSP later moves off Simple Start, the dormant `qbo_bills` / A/P
  entities and QBO Payroll entities become available — a versioned extension, not this slice.

## Cross-references

ADR-0001 (cloud keeps webhooks; local owns scheduled bulk) · ADR-0005 (source catalog & table
naming; fail-loud-on-missing-table) · ADR-0006 (IT Glue hub — **skipped** for pure finance) ·
ADR-0014 (the existing QBO payment-fact `qbo_purchases` + expense chart-of-accounts
`qbo_expense_account` — the connection + posture this ADR widens; `qbo_purchases` reused, not
duplicated) · ADR-0011 (immutable snapshot idiom the P&L report follows) · ADR-0018 / ADR-0019
(the W28/W29 LP "FE bronze migration first; ADR-phase-only; collectors gated; issue stays open"
convention this ADR mirrors) · frontend ADR-0042 (four-repo split — bulk off Azure compute) ·
frontend ADR-0082 / ADR-0083 / ADR-0085 (time/expense tracking + Simple Start `Purchase` — the
existing QBO readers) · frontend ADR-0017 (schema ownership — migrations are front-end-owned;
`0120` defines these finance tables). Issues: **#194** (epic — source-catalog expansion, split by
domain), **#197** (this child — **ADR phase here; the full-pull collectors follow at W32**; stays
open), **frontend #688** (finance-bronze migration `0120`), backend **#104** (QBO cloud read client
— latency-sensitive reads), **#195** / **#196** (sibling managed-estate / security-incident
domains).
