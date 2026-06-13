# `scheduled-tasks/` — task files & polling registry

One **scheduled task per `(source, entity)`** (CLAUDE.md §1). Each task file here is **short**:
import the module, initialize context, call one `get` + one `post`. All orchestration lives in
the task file so the functions stay reusable by backfills and ad-hoc runs. Tasks are registered
with `Register-ImperionTask` and run under the gMSA / service identity, "whether logged on or
not".

## Task-file pattern

```powershell
# <area>/<entity>.task.ps1 — keep it this short.
Import-Module ImperionPipeline
Initialize-ImperionContext
# get -> post; the function does the heavy lifting, the task just composes + is scheduled.
Invoke-Imperion<Entity>Sync   # or:  Get-Imperion... | Set-Imperion...ToBronze
```

Registration (run once, elevated, under the service identity):

```powershell
Register-ImperionTask -Name 'Imperion m365 Mail' `
  -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "C:\...\scheduled-tasks\m365\mail.task.ps1"' `
  -Interval Hourly
```

## Polling cadence registry

| Area | Task | Entity | Cadence | Why |
| --- | --- | --- | --- | --- |
| **m365** | `m365/mail` | Emails (filtered) | **Hourly** | Timely comms; filtered to Imperion↔client (low volume) |
| **m365** | `m365/teams-chat` | Teams chats (filtered) | **Hourly** | same as mail |
| **m365** | `m365/teams-meeting` | Teams meetings (filtered) | **Every 4h** | Meetings are less frequent |
| **m365** | `m365/users` | Users | **Daily** | Slow-changing |
| **m365** | `m365/devices` | Devices | **Daily** | Slow-changing |
| **m365** | `m365/intune-devices` | Intune device compliance | **Daily** | Per-device posture truth (ADR-0051 d6); gated on pending bronze migration |
| **m365** | `m365/defender` | Defender XDR incidents + alerts | **Hourly** | Operationally timely; change-detected upsert keeps re-runs cheap; gated on 0076 prod apply |
| **m365** | `m365/auth-methods` | Per-user MFA registration | **Daily** | Registration state is slow-changing (ADR-0051 posture); gated on 0077 prod apply |
| **azure** | `azure/inventory` | Subs/RGs/resources | **Daily** | Inventory drift is slow |
| **azure** | `azure/sentinel` | Sentinel rules/watchlists/workbooks | **Daily** | Config drift is slow; skips non-Sentinel workspaces |
| **autotask** | `autotask/companies` | Companies | **Daily** | Slow-changing |
| **autotask** | `autotask/contacts` | Contacts | **Daily** | Slow-changing |
| **autotask** | `autotask/contracts` | Contracts | **Daily** | Slow-changing |
| **autotask** | `autotask/tickets` | Tickets | **Every 15–30 min** | Bulk reconcile; webhooks (cloud) handle real-time |
| **itglue** | `itglue/organizations` | Organizations | **Daily** | Slow-changing |
| **itglue** | `itglue/contacts` | Contacts | **Daily** | Slow-changing |
| **itglue** | `itglue/configurations` | Configurations (devices) | **Daily** | Slow-changing |
| **itglue** | `itglue/export` | Full dataset | **Daily** | Documentation snapshot |
| **telivy** | `telivy/assessments` | Assessments | **Daily** | Assessments change slowly |
| **darkwebid** | `darkwebid/compromises` | Compromises | **Daily** | Vendor refreshes ~daily |
| **docusign** | `docusign/envelopes` | Envelopes (contracts) | **Daily** | Signing lifecycle is slow; gated on secrets |
| **unifi** | `unifi/devices` | Devices + config compliance | **Daily** | Per-customer credential; double-gated (credential + pending bronze migration) |
| **plaud** | `plaud/recordings` | Recordings (note + transcript) | **Daily** | Per-user OAuth token; double-gated (token freshness + pending bronze migration) |
| **posture** | `posture/service-principals` | Service principals | **Daily** | Credential-expiry watch |
| **posture** | `posture/secure-score` | Secure Score | **Daily** | One snapshot/day |
| **posture** | `posture/policies` | CA/Intune/Defender + drift | **Daily** | Config drift |
| **posture** | `posture/merge` | posture_policy + tenant_posture silver (all tenants) | **Daily, after secure-score + policies** | Classify the night's fresh bronze (ADR-0010) |
| **kqm** | `kqm/proposals` | Quotes/proposals | **Daily** | 60/min + 20k/day budget; gated on the API key; secret-bearing URLs never logged |
| **kaseya** | `kaseya/import` | Contracts/tickets/proposals | **Daily** | Legacy bulk reconcile |
| **meta** | `meta/social` | FB posts/comments/DMs + IG media/comments + merge | **Daily** | Organic social is slow-moving; DM senders → leads via the merge (issue #126) |
| **meta** | `meta/insights` | Page + IG insight snapshots + merge | **Daily** | period=day metrics yield one point/day; per-metric deprecation tolerance |

> Cadence is the **target**; tune per source rate-limits in `docs/integrations/<source>.md`.
> The authoritative as-built registry of *registered* tasks is
> [`docs/operations/scheduled-task-registry.md`](../docs/operations/scheduled-task-registry.md).

## Status

Task files land as their `get`/`post` functions are built and tested (build order:
connect → get → post → task). Landed: `posture/service-principals`, `autotask/contracts`,
`autotask/tickets`, `telivy/assessments`, `darkwebid/compromises`, `docusign/envelopes`
(gated on the SecretStore secrets — see `docs/integrations/docusign.md`), `m365/users`,
`m365/devices`, `itglue/organizations`, `itglue/contacts`, `itglue/configurations`,
`itglue/export`, `azure/inventory` (per-entity get → post composition; management groups
stay with `Invoke-ImperionAzureInventorySync`), `azure/sentinel` (the Sentinel get →
multi-table router post, issue #97), `kqm/proposals` (gated on the API key; verify
live field names with `Get-ImperionKqmFieldName` first — issue #98), and the m365
communications tasks `m365/mail`, `m365/teams-chat`, `m365/teams-meeting` (issue #100 —
double-gated: env-var config + migration 0065 prod apply; Teams reads additionally need
Microsoft's protected-API approval, see docs/integrations/m365-communications.md), and
the meta tasks `meta/social`, `meta/insights` (issue #126 — gated on
IMPERION_META_PAGE_ID + the SecretStore token + migration 0075 prod apply; registration
itself deferred to server bringup #102, see docs/integrations/meta.md), and
`m365/defender` (issue #138 — Defender XDR incidents + alerts, gated on migration 0076
prod apply; registration deferred to #102, see docs/integrations/defender-xdr.md), and
`m365/auth-methods` (issue #140 — per-user MFA registration, gated on migration 0077
prod apply; registration deferred to #102, see docs/integrations/entra-auth-methods.md).
Still to land: `autotask/companies`, `autotask/contacts`, the remaining posture tasks,
and `kaseya/import`.
