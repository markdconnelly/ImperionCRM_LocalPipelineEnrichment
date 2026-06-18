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
| **m365** | `m365/intune-apps` | Intune managed apps | **Daily** | Drillable app inventory (issue #143 / frontend #261); gated on DeviceManagementApps.Read.All grant + pending bronze migration |
| **m365** | `m365/defender` | Defender XDR incidents + alerts | **Hourly** | Operationally timely; change-detected upsert keeps re-runs cheap; gated on 0076 prod apply |
| **m365** | `m365/auth-methods` | Per-user MFA registration | **Daily** | Registration state is slow-changing (ADR-0051 posture); gated on 0077 prod apply |
| **m365** | `m365/sharepoint-sites` | SharePoint site inventory (metadata only) | **Daily** | Site inventory is slow-changing; NO file content (Files.Read.All pruned); gated on 0078 prod apply |
| **m365** | `m365/entra-groups` | Entra/M365 group inventory | **Daily** | Group inventory is slow-changing; change-detected upsert keeps re-runs cheap (0079 applied) |
| **m365** | `m365/entra-group-members` | Group membership edges | **Daily** | Membership is slow-changing; one members call per group; reaches the silver contact (0079 applied) |
| **azure** | `azure/inventory` | Subs/RGs/resources | **Daily** | Inventory drift is slow |
| **azure** | `azure/sentinel` | Sentinel rules/watchlists/workbooks | **Daily** | Config drift is slow; skips non-Sentinel workspaces |
| **azure** | `azure/dns-zones` | DNS zones + recordsets + write-probe (ADR-0063) | **Daily** | DNS drift is slow; Reader-only + permissions read-probe; gated on 0080 prod apply |
| **azure** | `azure/dns-resolve` | Public DNS resolution per account_domain (ADR-0063) | **Daily** | Ground-truth plane; no Microsoft auth (OS resolver + DoH); gated on 0081 account_domain |
| **azure** | `azure/dns-merge` | DNS golden/drift silver rollup → dns_domain (ADR-0063) | **Daily, after dns-zones + dns-resolve** | Reconciles both planes vs golden; idempotent upsert; gated on 0080 + 0081 prod apply |
| **azure** | `azure/cloud-resources` | Per-client subs/RGs/resources → CMDB cloud-asset bronze (ADR-0023, #201) | **Daily** | Cloud inventory drifts slowly; per-client-tenant fan-out (`IMPERION_M365_TENANT_IDS`); change-detected upsert keeps re-runs cheap; dormant-safe per-tenant catch; distinct from `azure/inventory` (partner-tenant posture, `azure_resources`); gated on per-client onboarding-app consent (FE 0130 bronze + 0139 silver applied; Pipeline #126 merge live) |
| **autotask** | `autotask/companies` | Companies | **Daily** | Slow-changing |
| **autotask** | `autotask/contacts` | Contacts | **Daily** | Slow-changing |
| **autotask** | `autotask/contracts` | Contracts | **Daily** | Slow-changing |
| **autotask** | `autotask/tickets` | Tickets | **Every 15–30 min** | Bulk reconcile; webhooks (cloud) handle real-time |
| **autotask** | `autotask/time-entries` | TimeEntries | **Hourly** | Authoritative bulk pull for time tracking (ADR-0082); cloud PL-2 does on-demand refresh; gated on AT credential |
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
| **kqm** | `kqm/opportunities` | Opportunity header → won-quote detail | **Daily** | Chains header (`kqm_opportunities`) → won-only detail (sections/lines/sales orders, #161); 60/min + 20k/day budget; gated on the API key; secret-bearing URLs never logged |
| **kaseya** | `kaseya/import` | Contracts/tickets/proposals | **Daily** | Legacy bulk reconcile |
| **easydmarc** | `easydmarc/domains` | Domain DMARC/SPF/DKIM/BIMI posture | **Daily** | Domain posture is slow-changing; company key, Bearer header (URLs not secret-bearing); double-gated on the API key + the proposed `easydmarc_domains` front-end migration (issue #122) |
| **qbo** | `qbo/purchases` | Purchases (Check/Expense) | **Daily** | Payment fact (frontend ADR-0082/ADR-0085); Simple Start has no AP → Bill/BillPayment unavailable, re-targets to Purchase; low volume; gated on QBO app reg (front-end `qbo_purchases` migration 0092 SHIPPED, #526); read-only, amount/payee never logged |
| **qbo** | `qbo/chart-of-accounts` | Expense-type chart-of-accounts | **Daily** | Category system of record (frontend ADR-0083); slow-changing; double-gated on QBO chart-of-accounts read scope (frontend #497) + front-end `qbo_expense_account` migration (frontend #592); read-only (app never writes QBO), admin maps account→expense_category (frontend #489) |
| **mileiq** | `mileiq/drives` | Business-classified drives (per connected employee) | **Daily** | Mileage capture (frontend ADR-0083); per-employee OAuth (backend custodies token, this repo reads it); triple-gated on MileIQ API creds (frontend #495) + backend OAuth custody + migrations 0088–0090 (frontend #494); business-only (personal drives never enter), no comp, locations/miles/amounts never logged |
| **meta** | `meta/social` | FB posts/comments/DMs + IG media/comments + merge | **Daily** | Organic social is slow-moving; DM senders → leads via the merge (issue #126) |
| **meta** | `meta/insights` | Page + IG insight snapshots + merge | **Daily** | period=day metrics yield one point/day; per-metric deprecation tolerance |
| **security** | `security/incidents` | Incident → alerts → evidence (+ `autotask_ticket_ref`) | **Hourly** | Operationally timely (ADR-0019, #196); read-only onboarding-app Graph; → `m365_incidents`/`m365_alerts`/`m365_evidence` (FE 0119 applied); DORMANT until creds (#102) + autotask_ticket_ref format confirm-before-live |
| **security** | `security/purview-compliance` | Purview compliance posture + drift (NO alerts) | **Daily** | Compliance config slow-changing (ADR-0019 §2); → `purview_compliance_policies`/`_golden` via the existing drift engine; silver merge held out until FE widens the policy_family CHECK; DORMANT until creds (#102) |
| **security** | `security/retention-sweep` | 180-day prune of `m365_incidents`/`alerts`/`evidence` ONLY | **Daily** | Autotask is durable SoR (ADR-0019 §3); leaf-first, idempotent, `-WhatIf`-aware, count-only logging; NOT interaction/purview/system-wide; first live run gated |

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
multi-table router post, issue #97), `kqm/opportunities` (header #160 + won-quote detail
#161 chained; gated on the API key; verify live field names with `Get-ImperionKqmFieldName`
first — issue #98), and the m365
communications tasks `m365/mail`, `m365/teams-chat`, `m365/teams-meeting` (issue #100 —
double-gated: env-var config + migration 0065 prod apply; Teams reads additionally need
Microsoft's protected-API approval, see docs/integrations/m365-communications.md), and
the meta tasks `meta/social`, `meta/insights` (issue #126 — gated on
IMPERION_META_PAGE_ID + the SecretStore token + migration 0075 prod apply; registration
itself deferred to server bringup #102, see docs/integrations/meta.md), and
`m365/defender` (issue #138 — Defender XDR incidents + alerts, gated on migration 0076
prod apply; registration deferred to #102, see docs/integrations/defender-xdr.md), and
`m365/auth-methods` (issue #140 — per-user MFA registration, gated on migration 0077
prod apply; registration deferred to #102, see docs/integrations/entra-auth-methods.md),
and `m365/sharepoint-sites` (issue #137 — SharePoint site inventory, metadata only /
never file content, gated on migration 0078 prod apply; registration deferred to #102,
see docs/integrations/sharepoint-sites.md), and `m365/entra-groups` (issue #150, split
from #139 — Entra/M365 group inventory, migration 0079 applied; registration deferred to
#102, see docs/integrations/entra-groups.md), and `m365/entra-group-members` (issue #139 -
group membership edges reaching the silver contact via member_external_id, migration 0079
applied; registration deferred to #102, see docs/integrations/entra-groups.md), and
`easydmarc/domains` (issue #122 — domain/DMARC posture, double-gated on the EasyDMARC API
key + the proposed `easydmarc_domains` front-end bronze migration; registration deferred to
#102, see docs/integrations/easydmarc.md).
Still to land: `autotask/companies`, `autotask/contacts`, the remaining posture tasks,
and `kaseya/import`.
