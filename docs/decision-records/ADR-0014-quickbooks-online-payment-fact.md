# ADR-0014: QuickBooks Online bronze pulls — the payment fact + the expense category SoR

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-13 (amended 2026-06-15, #168 — chart-of-accounts; amended 2026-06-15, #174 — BillPayment → Purchase for Simple Start) |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | frontend ADR-0082, frontend ADR-0083, frontend ADR-0085, frontend ADR-0042, ADR-0001, ADR-0005, ADR-0006 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as 0014; renumber to the next
> free local-pipeline ADR at merge if a concurrent branch takes it.

## Problem

Employee time-tracking (frontend ADR-0082) moves a timesheet to **Paid** only when expected pay
matches a **real payment**. The MSP pays its (v1, all-1099) employees as QuickBooks Online vendor
AP **bill-payments**. The backend Payroll Reconciliation (backend #105) needs that payment as a
queryable fact in the shared store — but QBO is a public, internet-facing API and a home server
behind NAT cannot receive its webhooks. Where does the scheduled bulk pull live, and what is
QBO's authority?

## Context

The four-repo split (frontend ADR-0042): all **scheduled bulk ingestion** lives in this repo;
**inbound webhooks** stay in the cloud Pipeline (ADR-0001). Backend BE-2 (#104) builds the
in-cloud QBO **read client** (token custody, on-demand reads). This decision covers the
**on-prem scheduled bronze bulk pull** — the same source, a different plane.

## Options considered

1. **Bulk-pull QBO bill-payments here → bronze; QBO authoritative for the payment fact only.**
2. Let the backend cloud client do the bulk pull too — but bulk/scheduled/high-volume is exactly
   what ADR-0042 moves off Azure compute; the cloud client stays for latency-sensitive reads.
3. Treat the app's payroll-approval as "paid" without a QBO match — rejected: loses the
   external truth that a payment actually happened (frontend ADR-0082 requires the match).

## Decision

A scheduled on-prem collector bulk-pulls the QBO **payment fact** into bronze, idempotent on the
QBO transaction `Id`. **QBO is read-only and authoritative for the payment fact ALONE — the app
never pays.** Pure finance data: flattens straight to Postgres, skips IT Glue (ADR-0006). The
collector is **deploy-ahead/gated** — it logs + exits until the QBO app registration lands.

> **Re-targeted 2026-06-15 (#174) — see the amendment below.** The original decision used the
> `BillPayment` entity (`Get-ImperionQboBillPayment` → `Set-ImperionQboBillPaymentToBronze` →
> `qbo_bill_payments`). Imperion's QBO company is **Simple Start**, which has NO Accounts Payable —
> `Bill`/`BillPayment` return "Feature Not Supported". The collector now uses the **`Purchase`**
> entity (`Get-ImperionQboPurchase` → `Set-ImperionQboPurchaseToBronze` → `qbo_purchases`,
> front-end migration 0092 / ADR-0085), same connect helper `Invoke-ImperionQboRequest`. The
> subscription is NOT upgraded.

## Consequences

### Security impact

Read-only OAuth2; no QBO write surface. The access token (`qbo-access-token`) EXPIRES (~1h) and
the refresh token rotates — a refresh failure fails closed (task logs + exits; no silent retry).
The payment **amount** and **vendor name** land in bronze (the fact) but are **never logged**
(metric counts only, CLAUDE.md §8). No comp data (pay_rate) is read or stored here — it stays in
the front-end finance-gated 0085 store.

### Cost impact

Negligible — low-volume daily incremental page-walk; idempotent content-hash skip avoids
rewriting unchanged rows.

### Operational impact

The **front-end `qbo_purchases` migration** (0092, #526) is **SHIPPED**, so one gate remains for
LIVE (not BUILD): the **QBO read-only app registration** + token custody (the standing
time-tracking blocker, shared with backend #104). Token refresh re-auth is an operator runbook
item (docs/integrations/quickbooks-online.md).

## Amendment 2026-06-15 (#168): expense chart-of-accounts pull

QBO is also the **category system of record** for expense tracking (frontend ADR-0083, epic
markdconnelly/ImperionCRM#482). A second scheduled on-prem collector
(`Get-ImperionQboExpenseAccount` → `Set-ImperionQboExpenseAccountToBronze`, reusing the connect
helper `Invoke-ImperionQboRequest` and the same `qbo-access-token` / `qbo-realm-id` secrets)
bulk-pulls QBO **Account** rows where `Classification = 'Expense'` into bronze
`qbo_expense_account`, idempotent on the QBO Account `Id`. Columns: `name, fully_qualified_name,
account_type, account_sub_type, classification, active, created_time, last_updated_time` + the
standard envelope.

- **Read-only — the app never writes QuickBooks.** A front-end admin maps each synced account to a
  clean website `expense_category` (frontend #489). When finance needs a missing category they
  create it in QuickBooks manually; the next pull surfaces it. This is the same one-way,
  read-only-and-authoritative posture as the payment fact, just for reference (category) data.
- **Reference data, not comp/PII.** Account names ("Travel", "Office Supplies") are not
  compensation and not personal data; the metric log records counts only (CLAUDE.md §8).
- Pure finance/reference data: flattens straight to Postgres, skips IT Glue (ADR-0006). The
  collector is **deploy-ahead/gated** — it logs + exits until both the QBO chart-of-accounts read
  scope (frontend markdconnelly/ImperionCRM#497) and the front-end `qbo_expense_account` migration
  (frontend #592, migration 0088; apply gated by frontend #494) land.
- **Boundary:** chart-of-accounts bulk sync ONLY; the backend QBO read client owns the
  bill-payment reconciliation read (this repo's bill-payment leg is the bulk fact above).

## Amendment 2026-06-15 (#174): re-target the payment fact BillPayment → Purchase (Simple Start)

Imperion's QBO company is **Simple Start**, which has **no Accounts Payable** — the `Bill` and
`BillPayment` entities the original decision modeled return **"Feature Not Supported"** from the
Intuit Accounting API. In Simple Start, 1099 contractor payments (and expense reimbursements) are
recorded as **Checks / Expenses**, exposed by the API as the **`Purchase`** entity. So the
authoritative payment fact re-targets `BillPayment` → `Purchase`. **The subscription is NOT being
upgraded** (front-end ADR-0085).

- **Collector.** `Get-ImperionQboPurchase` → `Set-ImperionQboPurchaseToBronze`, reusing the
  connect helper `Invoke-ImperionQboRequest` and the same `qbo-access-token` / `qbo-realm-id`
  secrets. Query `SELECT * FROM Purchase [WHERE MetaData.LastUpdatedTime > '<iso>']`, page-walk
  unchanged. Scheduled task renamed `qbo/bill-payments.task.ps1` → `qbo/purchases.task.ps1`.
- **Target.** Bronze `qbo_purchases` (front-end migration **0092**, markdconnelly/ImperionCRM#526
  / front-end ADR-0085; **drops + supersedes** 0091/`qbo_bill_payments`, which was empty and never
  wired). Idempotent on the QBO `Purchase.Id`. Columns: `txn_date, total_amount, payment_type,
  account_ref, account_name, entity_id, entity_type, entity_name, doc_number, currency,
  created_time, last_updated_time` + the standard envelope. The payee link is the existing
  `employee_profile.qb_vendor_id` (front-end migration 0085) = `Purchase.EntityRef.value`, reused
  unchanged.
- **Gate change.** The front-end `qbo_purchases` migration (0092) is **SHIPPED**, so the only
  remaining LIVE gate is the QBO app registration + token custody (unchanged, shared with backend
  #104). Same read-only / never-log-amount-or-payee posture.
- **Backend readers.** The Payroll Reconciliation (backend #105) and the expense-reimbursement
  reconciliation (front-end ADR-0083) now match expected pay/reimbursement to a `Purchase`.

## Future considerations

- Confirm the live `Purchase` shape against the real books (the doc's CONFIRM-BEFORE-LIVE list).
  *(Resolved 2026-06-15, #174: `Purchase` — not `Bill`/`BillPayment` — carries the 1099 payments
  on this Simple Start company; AP entities are unavailable. See the amendment below.)*
- Confirm the live Account shape and whether the `Classification = 'Expense'` filter or an
  explicit `AccountType` IN (...) filter best captures the expense chart-of-accounts (#168).
- W2 payroll (frontend ADR-0082 modeled-dormant) would add QBO Payroll entities later — a
  versioned extension, not this slice.
- A shared QBO bronze definition may later absorb the broader source-catalog QBO §2.6 proposal;
  this slice is the minimal payment-fact landing.

## Cross-references

frontend ADR-0082 (time-tracking design) · frontend ADR-0042 (four-repo split) · ADR-0001 (cloud
keeps webhooks) · ADR-0005 (source catalog & table naming) · ADR-0006 (IT Glue hub — skipped for
pure finance). Backend #104 (QBO cloud read client), #105 (Payroll Reconciliation).
