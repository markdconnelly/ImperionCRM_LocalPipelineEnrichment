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
| **azure** | `azure/inventory` | Subs/RGs/resources/Sentinel | **Daily** | Inventory drift is slow |
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
| **posture** | `posture/service-principals` | Service principals | **Daily** | Credential-expiry watch |
| **posture** | `posture/secure-score` | Secure Score | **Daily** | One snapshot/day |
| **posture** | `posture/policies` | CA/Intune/Defender + drift | **Daily** | Config drift |
| **posture** | `posture/merge` | posture_policy + tenant_posture silver (all tenants) | **Daily, after secure-score + policies** | Classify the night's fresh bronze (ADR-0010) |
| **kaseya** | `kaseya/import` | Contracts/tickets/proposals | **Daily** | Legacy bulk reconcile |

> Cadence is the **target**; tune per source rate-limits in `docs/integrations/<source>.md`.
> The authoritative as-built registry of *registered* tasks is
> [`docs/operations/scheduled-task-registry.md`](../docs/operations/scheduled-task-registry.md).

## Status

Task files land as their `get`/`post` functions are built and tested (build order:
connect → get → post → task). Landed: `posture/service-principals`, `autotask/contracts`,
`autotask/tickets`, `telivy/assessments`, `darkwebid/compromises`, `m365/users`,
`m365/devices`, `itglue/organizations`, `itglue/contacts`, `itglue/configurations`,
`itglue/export`, and `azure/inventory` (per-entity get → post composition; Sentinel +
management groups stay with `Invoke-ImperionAzureInventorySync` until the Sentinel get
lands). Still to land: the m365 communications tasks (`mail`, `teams-chat`,
`teams-meeting`), `autotask/companies`, `autotask/contacts`, the remaining posture tasks,
and `kaseya/import`.
