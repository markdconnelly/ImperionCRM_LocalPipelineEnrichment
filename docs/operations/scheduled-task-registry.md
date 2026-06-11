# Scheduled-task registry

The pipeline is **many small scheduled tasks** (one per sync cmdlet), not a monolith
(CLAUDE.md §1). Each runs under the dedicated gMSA/service account, "run whether logged on
or not." Register/update them with the **`Register-ImperionTask`** cmdlet (idempotent). Each
task command is `pwsh -Command "Import-Module ImperionPipeline; Initialize-ImperionContext;
<cmdlet>"`.

| Task | Cmdlet / task file | Suggested cadence | Notes |
| --- | --- | --- | --- |
| Entra service principals → IT Glue | `Invoke-ImperionServicePrincipalSync` | daily | partner tenant; GDAP loop optional |
| Azure + Sentinel inventory | `Invoke-ImperionAzureInventorySync` | daily | skips workspaces without Sentinel |
| Azure inventory (per-entity get → post) | `scheduled-tasks/azure/inventory.task.ps1` | daily | subscriptions → resource groups → resources via `Set-ImperionAzure*ToBronze`; Sentinel/mgmt-groups stay with the sync cmdlet above until the Sentinel get lands |
| Secure Score | `Invoke-ImperionSecureScoreSync` | daily | overall + control profiles |
| Security-posture policies + drift | `Invoke-ImperionPolicySync` | daily | CA/Intune/device-config/Autopilot/Defender; drift vs golden |
| **Posture silver merge (all tenants)** | `Invoke-ImperionPostureMerge` | daily 03:20 (after SecureScore + PolicySync) | classifies posture_policy + rolls up tenant_posture, unmapped tenants included (ADR-0010); **operator: re-run `Register-ImperionTask` once to register** |
| Autotask contracts | `scheduled-tasks/autotask/contracts.task.ps1` | daily | incremental on `lastModifiedDateTime` (`IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS`) |
| Autotask tickets | `scheduled-tasks/autotask/tickets.task.ps1` | every 15–30 min | bulk reconcile; webhooks (cloud Pipeline) handle real-time |
| M365 users | `scheduled-tasks/m365/users.task.ps1` | daily | → `m365_contacts` (ADR-0039 shape); GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| M365 devices | `scheduled-tasks/m365/devices.task.ps1` | daily | → `m365_devices` (ADR-0039 shape); GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| IT Glue organizations | `scheduled-tasks/itglue/organizations.task.ps1` | daily | → `itglue_companies` (ADR-0039 shape) |
| IT Glue contacts | `scheduled-tasks/itglue/contacts.task.ps1` | daily | → `itglue_contacts` (ADR-0039 shape) |
| IT Glue configurations | `scheduled-tasks/itglue/configurations.task.ps1` | daily | → `itglue_devices` (ADR-0039 shape) |
| IT Glue full export → Postgres | `scheduled-tasks/itglue/export.task.ps1` (`Invoke-ImperionITGlueExport`) | daily/12h | per-type + relationships; ad-hoc slices via `Invoke-ImperionITGlueExportToBronze` |
| Telivy assessments | `scheduled-tasks/telivy/assessments.task.ps1` | daily | → `televy_reports` (ADR-0039 shape) |
| Dark Web ID compromises | `scheduled-tasks/darkwebid/compromises.task.ps1` | daily | company credential from Key Vault (`conn-company-darkwebid`) |
| Kaseya proposals/contracts/tickets | `Invoke-ImperionKaseyaImport` | hourly–daily | bulk upsert, watermarked |
| GDAP relationship health | (build-order task) | hourly | fail-closed surfacing |
| **Gold knowledge + vectorization** | `Invoke-ImperionKnowledgeSync -Vectorize` | nightly 04:30 (after ingests) | composes knowledge_object from silver, chunks (v1), embeds via Voyage @ 1024; chunk-hash idempotent — no re-bill (ADR-0009) |

> **Grant prerequisite:** front-end migration 0044 grants the local-pipeline SP write on the
> 0038/0043 bronze tables only. The migration-0036 tables the m365/itglue per-object tasks
> target (`m365_contacts`, `m365_devices`, `itglue_companies`, `itglue_contacts`,
> `itglue_devices`) need a follow-up grant migration in the front-end repo before live runs.

## Conventions
- Each task invokes **one** module cmdlet after `Initialize-ImperionContext`. No business
  logic in the task definition.
- Tasks are **idempotent**; overlapping runs are prevented (`-MultipleInstances
  IgnoreNew`).
- Every run emits structured JSON logs to `logs/` (run id, source, counts, duration, cost).
- Cadence per source is documented in each `integrations/` doc; tune without code changes.
