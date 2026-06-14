# Integration — Autotask TimeEntries → bronze `autotask_time_entry` (issue #171)

Scheduled **bulk** pull of native Autotask **TimeEntries** (work allocated against tickets)
into the typed bronze table `autotask_time_entry` (front-end migration 0086, ADR-0082;
prod-applied). This is the **authoritative full/historical** pull — the local pipeline owns
the bulk window. The cloud Pipeline PL-2 (`ImperionCRM_Pipeline` #101) serves only the
on-demand "refresh now" path. The bronze→silver `time_record` merge is PL-1
(`ImperionCRM_Pipeline` #100): it resolves `autotask_resource_id` → employee via the 0085
mapping and folds the row into silver `time_record`, where Autotask **corroborates** the
authoritative website attendance (ADR-0082; website is the source of truth, Autotask is not).

Pure operational time data → flattens straight to Postgres; the IT Glue hub step is skipped
(CLAUDE.md §6).

## Auth & credentials (GATED until provisioned)

Reuses the shared Autotask context (`Get-ImperionAutotaskContext`) — the same SecretStore
secrets as every other Autotask collector (companies / contacts / contracts / tickets):

| Secret (SecretStore, CLAUDE.md §2) | Name key (`config/secret-names`) | Holds |
| --- | --- | --- |
| `autotask-integration-code` | `AutotaskIntegrationCode` | API integration tracking code |
| `autotask-username` | `AutotaskUserName` | API user (resource) login |
| `autotask-secret` | `AutotaskSecret` | API user secret |

**Gating (Mark — blocks LIVE not BUILD):** the Autotask **company credential** scoped to
TimeEntry read. With the secrets absent, `Get-ImperionAutotaskContext` cannot resolve the
zone and the scheduled task surfaces the failure on the next run; nothing is written. The
collector is **deploy-ahead safe** — no-op until the credential lands. Credentials/PII are
never logged.

## Endpoint & paging

| What | Entity | Filter |
| --- | --- | --- |
| All TimeEntries | `TimeEntries` | `id gte 0` (full backfill, default) |
| Incremental | `TimeEntries` | `lastModifiedDateTime gte {ISO}` (when `-SinceDays > 0`) |

Paged via the shared `Invoke-ImperionAutotaskRequest` (follows `pageDetails.nextPageUrl`;
429/503 backoff via `Invoke-ImperionRestWithRetry`).

## Field map (mirrors the PL-2 writer — CONFIRM against the live API on first pull)

`autotask_time_entry` is the **first typed bronze table** in this repo (every other bronze
table is text + jsonb). The collector therefore bypasses the text flattener
(`ConvertTo-ImperionFlatObject`) and emits **native CLR types** so Npgsql maps them to the
typed columns with no per-column SQL cast.

| Bronze column | Type | Autotask field (primary → fallback) | CLR type emitted |
| --- | --- | --- | --- |
| `external_ref` | text (UNIQUE) | `id` | string |
| `autotask_resource_id` | bigint | `resourceID` → `resourceId` | `long?` |
| `autotask_ticket_id` | bigint | `ticketID` → `ticketId` | `long?` |
| `work_date` | date | `dateWorked` → `workDate` | `DateOnly?` |
| `started_at` | timestamptz | `startDateTime` → `startTime` | `DateTimeOffset?` |
| `ended_at` | timestamptz | `endDateTime` → `endTime` | `DateTimeOffset?` |
| `hours_worked` | numeric | `hoursWorked` → `hoursToBill` | `decimal?` |
| `payload_bronze` | jsonb | *(full record)* | JSON string (cast `::jsonb`) |
| `last_seen_at` | timestamptz | *(write clock)* | `DateTimeOffset` (UTC) |

**Merge-owned columns — never written here:** `app_user_id`, `matched_at` (PL-1 resolves the
employee). The upsert's SET clause only touches the projected columns above, so a re-ingested
row keeps its resolution: ingestion can never un-resolve a matched entry.

## Idempotency & cadence

- **Upsert on `external_ref`** (the Autotask TimeEntry id; the table's UNIQUE key),
  `-NoChangeDetect` (no `content_hash` column — change is resolved in the merge, ADR-0039
  idiom). Re-runs converge; never duplicate.
- **Cadence: Hourly** (`scheduled-tasks/autotask/time-entries.task.ps1`). Default
  `-SinceDays 7` covers the weekly Mon–Sun timesheet window with margin; set
  `IMPERION_AUTOTASK_TIME_SINCE_DAYS=0` for a full authoritative backfill.
- **Telemetry:** the shared post-writer (`Invoke-ImperionBronzePost`) emits the standard
  metric log line (table, scanned/inserted/updated/unchanged) per run.

## Provenance & posture

- Read-only against Autotask; no comp/pay data touches this repo (pay_rate stays in the
  front-end finance-gated 0085 store).
- The Autotask Resource → employee join lives in the 0085 mapping (admin-confirmed in the
  front-end mapping UI); this collector lands the raw resource id only.

## Register the task

```powershell
Register-ImperionTask -Name 'Imperion autotask time-entries' `
  -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\autotask\time-entries.task.ps1"' `
  -Interval Hourly
```
