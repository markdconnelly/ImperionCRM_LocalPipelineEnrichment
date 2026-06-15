# ADR-0015: Receipt-blob 90-day lifecycle, guarded by verified-in-Autotask

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-14 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | frontend ADR-0083, frontend ADR-0042, ADR-0001, ADR-0002 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as 0015; renumber to the next
> free local-pipeline ADR at merge if a concurrent branch takes it.

## Problem

Expense receipts (frontend ADR-0083, migration 0089) are uploaded by employees to a **private
Azure storage account**, then pushed by the backend to Autotask as **ExpenseItemAttachments** and
**verified stored** (read-back). Once verified, Autotask is the durable system-of-record and the
storage-account copy is redundant. We want to reclaim that storage on a **90-day** cadence — but
deleting a receipt that did NOT actually land in Autotask would destroy the only copy. Where does
the lifecycle enforcer run, and how is that data-loss risk made impossible?

## Context

The four-repo split (frontend ADR-0042): all **scheduled / compute-heavy** work runs on-prem here;
inbound webhooks stay in the cloud Pipeline (ADR-0001). The receipt blob lives in the same private
storage account this repo's cert SP already holds the **Storage data-plane write** grant for
(CLAUDE.md §2 — the one write grant this needs). `receipt_attachment` carries the lifecycle state:
`verified_in_autotask`, `autotask_attachment_id`, `uploaded_at`, `blob_path`, `blob_deleted_at`
(migration 0089). The local-pipeline Postgres role holds **SELECT + UPDATE** on that table only —
it can stamp `blob_deleted_at` but never delete or insert rows.

## Options considered

1. **Scheduled on-prem enforcer; delete the blob ONLY when `verified_in_autotask = true`, stamp
   `blob_deleted_at`; an aged-but-unverified receipt is retained and flagged.** (Chosen.)
2. Delete purely on age (uploaded_at > 90d) — rejected: a receipt stuck unverified (Autotask push
   failed, never retried) would lose its only copy. Violates the ADR-0083 §Receipts invariant.
3. Run the lifecycle in the backend/cloud — rejected: it is scheduled bulk maintenance, exactly
   what ADR-0042 moves off Azure compute, and the cert SP that holds the storage write grant lives
   here.

## Decision

A scheduled on-prem cmdlet **`Invoke-ImperionReceiptLifecycle`** (the `Imperion-ReceiptLifecycle`
task) enforces the 90-day blob lifecycle:

- Selects only receipts that are **all of** `blob_deleted_at IS NULL`, `verified_in_autotask =
  true`, and `uploaded_at < now() - 90 days`.
- Per row, **re-asserts** `verified_in_autotask` with a fresh read before the irreversible delete
  (defence-in-depth — a future query change alone can never bypass the guard), deletes the blob via
  the primitive **`Remove-ImperionStorageBlob`** (cert-backed Storage data-plane DELETE), then
  stamps `blob_deleted_at = now()`.
- An aged-but-**unverified** receipt is **retained and surfaced as a count-only `Warn`** for
  follow-up — never deleted. This is the ADR-0083 §Receipts safety invariant, enforced in both the
  SQL `WHERE` and the per-row re-check.
- **Idempotent / resumable** (CLAUDE.md §6): already-deleted rows are excluded; an
  already-absent blob (404) is a no-op that still stamps `blob_deleted_at`, so a re-run converges.
  A failing receipt is isolated, logged count-only, and retried next run — it never blocks the
  batch. Honours `-WhatIf`/`-Confirm` (the cmdlet is `ConfirmImpact = High` — the scheduled task
  passes `-Confirm:$false`); a dry run reports the eligible + flagged sets without touching a thing.

`Remove-ImperionStorageBlob` mints a short-lived Storage data-plane token via the certificate SP
(`Get-ImperionStorageToken`, the agreed Storage write grant) and issues an authenticated TLS
`DELETE`. No new write capability is added — the storage write grant already exists (CLAUDE.md §2).

## Consequences

### Security impact

The one irreversible operation this repo performs on client-adjacent data. Risk is data loss, not
exfiltration, and it is gated three ways: (1) the verified-in-Autotask SQL guard, (2) the per-row
re-verify, (3) `ConfirmImpact = High` + `-WhatIf`. The Postgres role is SELECT+UPDATE on
`receipt_attachment` only (cannot delete rows). **No PII, no receipt content, no filenames, no blob
paths are logged** — only counts and opaque receipt ids (CLAUDE.md §8). The Storage write grant is
the pre-existing one; nothing widens.

### Cost impact

Negligible compute; the point is to *reduce* storage cost by reclaiming verified-redundant blobs
after 90 days. No embedding/LLM calls.

### Operational impact

Two Mark-gated prerequisites block LIVE (not BUILD): the **private storage account + lifecycle**
(frontend #496) and **migrations 0088–0090 applied** (frontend #494 — schema verified prod-applied
2026-06-14). The task is safe to register deploy-ahead: with an empty/clean table it scans zero
rows and exits. A persistent unverified backlog (rising `flaggedUnverified`) signals a backend
push/verify problem upstream — surfaced as a `Warn`, not silently absorbed.

## Future considerations

- A retention period other than 90 days is a single `-RetentionDays` override, no code change.
- If Autotask custody is ever proven unreliable, the guard already fails safe (retain + flag); the
  backlog metric is the early-warning signal.

## Cross-references

frontend ADR-0083 (expense capture + receipt custody) · frontend ADR-0042 (four-repo split) ·
ADR-0001 (cloud keeps webhooks; bulk runs here) · ADR-0002 (certificate-rooted unattended exec +
the Storage write grant). frontend migration 0089 (`receipt_attachment`), #494/#496 (gates).
Issue #169.
