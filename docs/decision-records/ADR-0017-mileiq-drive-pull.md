# ADR-0017: Scheduled per-employee MileIQ drive pull → `mileiq_drive` bronze

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-14 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | frontend ADR-0083, frontend ADR-0082, frontend ADR-0042, ADR-0001, ADR-0005, ADR-0006, ADR-0014 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as 0017; renumber to the next
> free local-pipeline ADR at merge if a concurrent branch takes it.

## Problem

Employee expense tracking (frontend ADR-0083) captures **mileage** from **MileIQ** via per-user
read-only OAuth. The silver `expense_item` (mileage leg) needs each employee's
**business-classified** drives as a queryable bronze fact in the shared store. MileIQ is a
public, internet-facing API and a home server behind NAT cannot receive its webhooks. Where does
the scheduled bulk pull live, how does it authenticate per employee, and how does it stay
dormant until credentials exist?

## Context

The four-repo split (frontend ADR-0042): all **scheduled bulk ingestion** lives in this repo;
**inbound webhooks** + **OAuth handshakes / token custody** stay in the cloud planes (ADR-0001;
the backend owns OAuth, CLAUDE.md §1). MileIQ is **per-employee** OAuth — unlike the MSP-wide QBO
(ADR-0014) or KQM keys, there is one token per connected employee. The backend custodies each
employee's refresh token in Key Vault and surfaces a short-lived access token; this repo reads
that token only.

## Options considered

1. **Scheduled on-prem per-employee collector → bronze; backend custodies tokens, this repo
   reads them per employee from Key Vault/SecretStore.** (Chosen.)
2. Have the backend cloud client do the bulk pull too — rejected: bulk/scheduled/high-volume is
   exactly what ADR-0042 moves off Azure compute.
3. Perform the OAuth handshake / refresh here — rejected: crosses the system boundary (backend
   owns OAuth handshakes and refresh-token custody); a home-server cert must not custody every
   employee's MileIQ refresh token.

## Decision

A scheduled on-prem collector (`Get-ImperionMileIqDrive` → `Set-ImperionMileIqDriveToBronze`,
connect helper `Invoke-ImperionMileIqRequest`, private per-user token resolver
`Resolve-ImperionMileIqAccessToken`) pulls **business-classified** MileIQ drives **per connected
employee** into typed bronze `mileiq_drive`, idempotent on `mileiq_drive_id`.

- **Connected employees** come from silver `employee_profile.mileiq_user_id` (migration 0088);
  `app_user_id` is stamped where resolved, NULL otherwise (the merge resolves later — the
  time-entry idiom, ADR-0082).
- **Per-employee token** resolves from `mileiq-token-<userId>` (SecretStore mirror) then
  `MileIQ-Token-<userId>` (Key Vault original, backend-custodied). A missing token →
  **skip that employee** (`$null`, never a throw): **dormant-per-employee, fail closed**.
- **Business-only, no comp.** Only `classification=business` drives are requested; **personal
  drives never enter** (ADR-0083). `suggested_rate`/`suggested_amount` are MileIQ's IRS-style
  suggestion, **not** compensation; no comp data is read or written.
- Pure expense data: flattens straight to Postgres, skips IT Glue (ADR-0006). Typed bronze table
  (native CLR types, like `autotask_time_entry`); `mileiq_drive` is **front-end migration 0089**
  — this repo never creates it.
- **Deploy-ahead/gated:** the task logs + exits cleanly until (a) MileIQ External API creds
  (frontend #495), (b) backend OAuth custody live, and (c) migrations 0088–0090 applied
  (frontend #494). Code ships now; runs live only when the gates clear.

## Consequences

### Security impact

Read-only OAuth2; no MileIQ write surface. Per-employee access tokens are read, never the
refresh tokens (backend custody, CLAUDE.md §1). Token rides a Bearer **header**, never a
querystring — URLs are not secret-bearing. A drive's locations/miles/amounts are PII-bearing and
are **never logged** (metric counts only, CLAUDE.md §8). Fail-closed: an unconnected /
consent-revoked employee is skipped, never touched (CLAUDE.md §3). No comp data here.

### Cost impact

Negligible — low-volume daily incremental page-walk per connected employee; idempotent upsert on
`mileiq_drive_id` avoids rewriting unchanged rows.

### Operational impact

Three gates block LIVE (not BUILD): MileIQ API creds (frontend #495), backend OAuth custody, and
the front-end `mileiq_drive` migration 0089 (frontend #494). **Front-end follow-up `frontend
#590` (filed from #167) requests/confirms the `mileiq_drive` 0089 bronze migration** (schema is
front-end-owned, CLAUDE.md §1). Per-employee token re-auth (consent expiry) is an operator runbook item
(docs/integrations/mileiq.md).

## Future considerations

- Confirm the live MileIQ drives shape against the real API once creds land (the
  CONFIRM-BEFORE-LIVE list in docs/integrations/mileiq.md): base host, drives path, paging param
  names, response wrapper.
- Out-of-pocket / receipt-based expense capture (the other ADR-0083 leg) is a separate slice; this
  ADR covers the mileage pull only.

## Cross-references

frontend ADR-0083 (expense tracking) · frontend ADR-0082 (time-tracking, app_user resolution
idiom) · frontend ADR-0042 (four-repo split) · ADR-0001 (cloud keeps webhooks/OAuth) · ADR-0005
(source catalog & table naming) · ADR-0006 (IT Glue hub — skipped for pure expense) · ADR-0014
(QBO deploy-ahead/gated precedent). frontend #494 (apply migrations 0088–0090), #495 (MileIQ API
creds), backend MileIQ OAuth custody issue.
