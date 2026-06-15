# Integration — MileIQ drives → bronze `mileiq_drive` (issue #167)

Scheduled **per-connected-employee** pull of **business-classified** MileIQ drives into the
typed bronze table `mileiq_drive` (front-end migration 0089, ADR-0083). This is the
authoritative scheduled mileage capture — the local pipeline owns the historical window; any
on-demand "refresh now" stays in the cloud Pipeline. The bronze→silver `expense_item` merge
(mileage leg) resolves `mileiq_user_id` → employee and folds drives into silver as mileage
expense items (ADR-0083).

Pure expense data → flattens straight to Postgres; the IT Glue hub step is skipped
(CLAUDE.md §6).

## Per-employee OAuth — the backend custodies, this repo reads

MileIQ is **per-user read-only OAuth**. The system boundary (CLAUDE.md §1): the **backend**
owns the OAuth handshake and **custodies each employee's refresh token in Key Vault** (backend
MileIQ OAuth issue); this repo **only reads the short-lived per-employee access token** the
backend surfaces — it never holds a refresh token and never performs the OAuth dance.

The set of connected employees is read from silver **`employee_profile`** (the email-resolved
`mileiq_user_id` mapping, migration 0088): one pull per row with a `mileiq_user_id`. Per-user
tokens are keyed by the MileIQ user id, so the secret **names are prefixes**, not single titles:

| Secret (per employee) | Name key (`config/secret-names`) | Resolution order |
| --- | --- | --- |
| `mileiq-token-<mileiqUserId>` (SecretStore mirror) | `MileIqTokenPrefix` (`mileiq-token-`) | 1st — when the vault is unlocked this run |
| `MileIQ-Token-<mileiqUserId>` (Key Vault original) | `MileIqTokenVaultPrefix` (`MileIQ-Token-`) | 2nd — backend-custodied, read by the cert SP |

`Resolve-ImperionMileIqAccessToken` returns `$null` (never throws) when neither store has the
employee's token. **Dormant-per-employee, fail closed (CLAUDE.md §3):** an unconnected /
consent-revoked employee is **skipped cleanly** — one unconnected user never fails the whole
pull, and an identity with no current credential is never touched.

## Gating (Mark — blocks LIVE, not BUILD)

Three gates block a live run; with any unmet the scheduled task logs the gap and exits cleanly
(deploy-ahead, the QBO/Plaud idiom):

1. **MileIQ External API credentials** — `markdconnelly/ImperionCRM#495`.
2. **Backend MileIQ OAuth custody live** — the backend mints/refreshes per-employee tokens into
   Key Vault.
3. **Front-end migrations 0088–0090 applied** — `markdconnelly/ImperionCRM#494`. The
   `mileiq_drive` bronze table itself is **migration 0089**, owned by the front-end repo
   (schema-ownership, CLAUDE.md §1). This repo never creates it; it fails loudly if absent.
   **Front-end follow-up `markdconnelly/ImperionCRM#590` (filed from #167) requests/confirms the
   `mileiq_drive` 0089 migration.**

## Endpoint & paging

| What | Path | Filter |
| --- | --- | --- |
| Business drives | `GET {base}/drives` | `classification=business` (always; personal drives never enter) |
| Incremental | `GET {base}/drives` | `&startDate={yyyy-MM-dd}` when `-SinceDays > 0` |

Default base `https://api.mileiq.com`. Paged via `Invoke-ImperionMileIqRequest` (`skip`/`take`
windows; stops on a short page; 429/503 backoff via `Invoke-ImperionRestWithRetry`). The token
rides an `Authorization: Bearer` header — **never the querystring** — so request URLs are not
secret-bearing.

> **CONFIRM BEFORE LIVE USE:** the base host, the exact drives path, the
> `classification`/`startDate`/`skip`/`take` parameter names, and the response wrapper
> (`{ drives: [...] }` vs a bare array) are modeled from the documented API but **UNVERIFIED**
> until the credentials land. Each typed field leads with the documented name and keeps a short
> fallback chain; an unmatched field lands NULL and nothing is lost (full payload in
> `payload_bronze`).

## Field map (CONFIRM against the live API on first pull)

`mileiq_drive` is a **typed** bronze table (like `autotask_time_entry`), so the collector
bypasses the text flattener and emits **native CLR types** Npgsql maps to the typed columns.

| Bronze column | Type | MileIQ field (primary → fallback) | CLR type emitted |
| --- | --- | --- | --- |
| `mileiq_drive_id` | text (UNIQUE) | `id` → `driveId` → `drive_id` | string |
| `mileiq_user_id` | text | *(from `employee_profile`)* | string |
| `app_user_id` | text / uuid | *(from `employee_profile`, NULL ok)* | string / `$null` |
| `drive_date` | date | `driveDate` → `date` → `startDate` → `startTime` | `DateOnly?` |
| `miles` | numeric | `miles` → `distance` → `distanceMiles` | `decimal?` |
| `origin` | text | `startLocation.name` → `origin` → `startName` → `startAddress` | string |
| `destination` | text | `endLocation.name` → `destination` → `endName` → `endAddress` | string |
| `suggested_rate` | numeric | `suggestedRate` → `rate` → `mileageRate` | `decimal?` |
| `suggested_amount` | numeric | `suggestedAmount` → `value` → `amount` | `decimal?` |
| `payload_bronze` | jsonb | *(full record)* | JSON string (cast `::jsonb`) |
| `last_seen_at` | timestamptz | *(write clock)* | `DateTimeOffset` (UTC) |

**`suggested_rate` / `suggested_amount` are MileIQ's own built-in IRS-style suggestion — NOT
employee compensation.** No comp data (pay/reimbursement rate) is read or written here; the
front-end finance store owns any reimbursable rate (ADR-0083).

**Merge-owned column — never written here:** `matched_at` (the merge resolves the employee).
`app_user_id` IS projected (collector resolves from `employee_profile` where possible, NULL
otherwise). The upsert's SET clause only touches the projected columns, so a re-ingested row
keeps its resolution.

## Idempotency & cadence

- **Upsert on `mileiq_drive_id`** (the stable MileIQ drive id; the table's UNIQUE key),
  `-NoChangeDetect` (no `content_hash` column — change is resolved in the merge, ADR-0039
  idiom). Re-runs converge; never duplicate.
- **Cadence: Daily** (`scheduled-tasks/mileiq/drives.task.ps1`). Default `-SinceDays 7`; set
  `IMPERION_MILEIQ_SINCE_DAYS=0` for a full authoritative backfill.
- **Telemetry:** the shared post-writer (`Invoke-ImperionBronzePost`) emits the standard metric
  log line (table, scanned/inserted/updated/unchanged) per run.

## Provenance & posture

- Read-only against MileIQ; per-employee OAuth, fail closed. **Personal drives never enter**
  (business classification filter); **no comp data** is read or written.
- A drive's locations, miles, and amounts are **never logged** (metric counts only, CLAUDE.md
  §8) — they are PII-bearing (where an employee was) and land only in bronze.

## Register the task

```powershell
Register-ImperionTask -Name 'Imperion mileiq drives' `
  -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\mileiq\drives.task.ps1"' `
  -Interval Daily
```
