# ADR-0010: Posture silver bulk merge — the scheduled twin of the cloud's on-demand refresh

| Field | Value |
|---|---|
| **Status** | Accepted (2026-06-11) |
| **Issue** | #88 (sub-issue of #74) |
| **Cross-references** | frontend ADR-0051 (posture model, table specs) · cloud pipeline ADR-0015 (account-scoped on-demand refresh) · this repo's ADR-0008 (golden states & drift) |

## Context

Frontend ADR-0051 §2 locked a two-tier refresh for posture silver: the **on-prem
pipeline owns scheduled bulk merges** (all tenants, on a cadence — this machine has the
resources) and the **cloud pipeline owns narrow on-demand refreshes** (one account's
mapped tenants, behind `POST /api/refresh {source:'posture', accountId}` — cloud
pipeline ADR-0015, already live). The silver pair (`posture_policy`, `tenant_posture`,
frontend migration 0062) is applied to prod and the GUI reads it (frontend #93/#94),
but only the on-demand half wrote it. Without the bulk twin, a tenant's posture is only
ever as fresh as the last time someone clicked Refresh on its account.

## Decision

`Invoke-ImperionPostureMerge` + the daily `Imperion-PostureMerge` scheduled task (03:20,
after SecureScore 02:45 and PolicySync 03:00 so it classifies the night's fresh bronze):

1. **Tenant scope = the whole posture estate.** Tenants are enumerated from the five
   observed bronze tables, the five golden tables, AND `secure_scores` — **including
   unmapped tenants** (ADR-0051: posture for an unmapped tenant still lands and
   surfaces; `tenant_posture` is keyed by tenant GUID, not FK'd to the mapping).
2. **Classification parity is a pinned contract.** The per-family FULL OUTER JOIN
   INSERT…SELECT and its CASE (`ungoverned` / `missing` / `compliant` / `drift`) are
   byte-equivalent to `Get-ImperionPolicyDrift` and the cloud's `posture-run.ts`. A
   Pester test pins the SQL here; the cloud repo pins its copy. **If one changes,
   change all three.**
3. **Replace-per-merge inside one transaction per tenant.** `posture_policy` is current
   state: DELETE + five INSERTs + the `tenant_posture` rollup upsert commit atomically,
   so readers never see a partial mix. A failing tenant rolls back its own transaction,
   logs, and never blocks the fleet — the next nightly run retries it.
4. **Rollup semantics match the cloud:** latest `secure_scores` row (bronze is all-text
   — numeric casts are regex-guarded so junk lands NULL, never throws), classification
   counts, and `exposures_open` = the owning account's unresolved `credential_exposure`
   rows resolved through `account_tenant` (an unmapped tenant rolls up 0).

The quarterly `posture_snapshot` job is deliberately NOT here — it waits on the
frontend `posture_snapshot(_pillar)` migration (#89; frontend issue filed).

## Consequences

- Every tenant's posture silver is at most a day stale without anyone clicking
  anything; the GUI's Refresh button remains the "right now" path.
- Three implementations now share one classification rule; the parity pin makes
  divergence a test failure instead of a silent data bug.
- The operator must re-run `Register-ImperionTask` once to register the new task
  (surfaced in docs/operations/scheduled-task-registry.md).

## Security impact

Pure SQL over tables the pipeline role already reads/writes (frontend migration 0062
grants). No Graph calls, no new scopes, no secrets. Per-tenant isolation holds: every
statement is keyed to one tenant GUID; the only cross-table join is through the
admin-managed `account_tenant` mapping.
