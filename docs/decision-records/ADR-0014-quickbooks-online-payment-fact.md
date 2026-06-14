# ADR-0014: QuickBooks Online vendor bill-payments as the authoritative payment fact

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-13 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | frontend ADR-0082, frontend ADR-0042, ADR-0001, ADR-0005, ADR-0006 |

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

A scheduled on-prem collector (`Get-ImperionQboBillPayment` → `Set-ImperionQboBillPaymentToBronze`,
connect helper `Invoke-ImperionQboRequest`) bulk-pulls QBO **BillPayment** rows into bronze
`qbo_bill_payments`, idempotent on the QBO payment `Id`. **QBO is read-only and authoritative for
the payment fact ALONE — the app never pays.** Pure finance data: flattens straight to Postgres,
skips IT Glue (ADR-0006). The collector is **deploy-ahead/gated** — it logs + exits until both
the QBO app registration and the front-end `qbo_bill_payments` migration land.

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

Two gates block LIVE (not BUILD): the **QBO read-only app registration** + token custody (the
standing time-tracking blocker, shared with backend #104) and the **front-end
`qbo_bill_payments` migration** + local-pipeline grant. Token refresh re-auth is an operator
runbook item (docs/integrations/quickbooks-online.md).

## Future considerations

- Confirm the live BillPayment shape against the real books; verify whether `Purchase`/`Bill`
  also carry 1099 contractor payments (the doc's CONFIRM-BEFORE-LIVE list).
- W2 payroll (frontend ADR-0082 modeled-dormant) would add QBO Payroll entities later — a
  versioned extension, not this slice.
- A shared QBO bronze definition may later absorb the broader source-catalog QBO §2.6 proposal;
  this slice is the minimal payment-fact landing.

## Cross-references

frontend ADR-0082 (time-tracking design) · frontend ADR-0042 (four-repo split) · ADR-0001 (cloud
keeps webhooks) · ADR-0005 (source catalog & table naming) · ADR-0006 (IT Glue hub — skipped for
pure finance). Backend #104 (QBO cloud read client), #105 (Payroll Reconciliation).
