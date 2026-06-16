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
| Azure inventory (per-entity get → post) | `scheduled-tasks/azure/inventory.task.ps1` | daily | subscriptions → resource groups → resources via `Set-ImperionAzure*ToBronze`; mgmt-groups stay with the sync cmdlet above |
| Sentinel objects (per-entity get → post) | `scheduled-tasks/azure/sentinel.task.ps1` | daily | `Get-ImperionSentinelObject` → `Set-ImperionSentinelToBronze` (multi-table router, sentinel_* set); existing Reader grant only (#97) |
| Secure Score | `Invoke-ImperionSecureScoreSync` | daily | overall + control profiles |
| Security-posture policies + drift | `Invoke-ImperionPolicySync` | daily | CA/Intune/device-config/Autopilot/Defender; drift vs golden |
| **Posture silver merge (all tenants)** | `Invoke-ImperionPostureMerge` | daily 03:20 (after SecureScore + PolicySync) | classifies posture_policy + rolls up tenant_posture, unmapped tenants included (ADR-0010); **operator: re-run `Register-ImperionTask` once to register** |
| **Posture snapshots (Imperion Secure Score)** | `Invoke-ImperionPostureSnapshot` | daily 03:40 (after PostureMerge) — self-gates to calendar quarters | immutable posture_snapshot(+pillar) per mapped account, Score Model v1 parity-pinned to frontend imperion-score.ts (ADR-0011); on-demand/QBR triggers bypass the gate; registered by the same `Register-ImperionTask` run |
| Autotask contracts | `scheduled-tasks/autotask/contracts.task.ps1` | daily | incremental on `lastModifiedDateTime` (`IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS`) |
| Autotask tickets | `scheduled-tasks/autotask/tickets.task.ps1` | every 15–30 min | bulk reconcile; webhooks (cloud Pipeline) handle real-time |
| M365 users | `scheduled-tasks/m365/users.task.ps1` | daily | → `m365_contacts` (ADR-0039 shape); GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| M365 devices | `scheduled-tasks/m365/devices.task.ps1` | daily | → `m365_devices` (ADR-0039 shape); GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| Intune device compliance | `scheduled-tasks/m365/intune-devices.task.ps1` | daily | → `intune_managed_devices` (flat compliance columns, frontend ADR-0051 d6, issue #75); GATED — pending front-end bronze migration; single-tenant default, fan-out via `IMPERION_M365_TENANT_IDS` |
| Intune managed apps | `scheduled-tasks/m365/intune-apps.task.ps1` | daily | → `intune_managed_apps` (flat publishing/assignment columns, issue #143 / frontend ImperionCRM #261); GATED — pending DeviceManagementApps.Read.All grant + front-end bronze migration; single-tenant default, fan-out via `IMPERION_M365_TENANT_IDS` |
| Entra domains (tenant hygiene) | `scheduled-tasks/m365/entra-domains.task.ps1` | daily | → `entra_domains` (issue #142 / front-end #260, `Domain.Read.All`); GATED — logs+exits until the #260 bronze migration lands; single-tenant default, GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| Entra app registrations (tenant hygiene) | `scheduled-tasks/m365/entra-app-registrations.task.ps1` | daily | → `entra_app_registrations` (issue #142 / front-end #260, `Application.Read.All`); credential count + nearest expiry are the hygiene signal; GATED — logs+exits until #260 migration lands; GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| Entra role assignments (tenant hygiene) | `scheduled-tasks/m365/entra-role-assignments.task.ps1` | daily | → `entra_role_assignments` (issue #142 / front-end #260, `RoleManagement.Read.Directory`, `$expand=roleDefinition,principal`); privileged-membership signal; GATED — logs+exits until #260 migration lands; GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| Sensitivity labels (info protection) | `scheduled-tasks/m365/sensitivity-labels.task.ps1` | daily | → `sensitivity_labels` (issue #141 / front-end #259, `SensitivityLabels.Read.All`); classification taxonomy; benchmark-vs-golden runs in front-end posture merge (#259); GATED — logs+exits until #259 migration lands; GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| Custom security attribute definitions (info protection) | `scheduled-tasks/m365/custom-security-attributes.task.ps1` | daily | → `custom_security_attribute_definitions` (issue #141 / front-end #259, `CustomSecAttributeDefinition.Read.All`, `$expand=allowedValues`); DEFINITIONS only (assignments deferred, PII); also needs **Attribute Definition Reader** role; GATED — logs+exits until #259 migration lands; GDAP fan-out via `IMPERION_M365_TENANT_IDS` |
| M365 mail (cross-org) | `scheduled-tasks/m365/mail.task.ps1` | hourly | → `m365_mail_messages` (migration 0065, source `m365_email`); DOUBLE-GATED — `IMPERION_M365_MAILBOXES`/`IMPERION_M365_CLIENT_DOMAINS` env config + 0065 prod apply (docs/integrations/m365-communications.md) |
| M365 Teams chats (cross-org) | `scheduled-tasks/m365/teams-chat.task.ps1` | hourly | → `m365_teams_chats` (migration 0065, source `m365_teams`, collector `user` → `user_upn`); TRIPLE-GATED — env config + 0065 prod apply + Microsoft protected-API approval for chat reads |
| M365 Teams meetings (cross-org) | `scheduled-tasks/m365/teams-meeting.task.ps1` | every 4h | → `m365_teams_meetings` (migration 0065, source `m365_teams`); DOUBLE-GATED — env config + 0065 prod apply (calendar reads are NOT protected-API gated) |
| IT Glue organizations | `scheduled-tasks/itglue/organizations.task.ps1` | daily | → `itglue_companies` (ADR-0039 shape) |
| IT Glue contacts | `scheduled-tasks/itglue/contacts.task.ps1` | daily | → `itglue_contacts` (ADR-0039 shape) |
| IT Glue configurations | `scheduled-tasks/itglue/configurations.task.ps1` | daily | → `itglue_devices` (ADR-0039 shape) |
| IT Glue full export → Postgres | `scheduled-tasks/itglue/export.task.ps1` (`Invoke-ImperionITGlueExport`) | daily/12h | per-type + relationships; ad-hoc slices via `Invoke-ImperionITGlueExportToBronze` |
| Telivy assessments | `scheduled-tasks/telivy/assessments.task.ps1` | daily | → `televy_reports` (ADR-0039 shape) |
| Dark Web ID compromises | `scheduled-tasks/darkwebid/compromises.task.ps1` | daily | company credential from Key Vault (`conn-company-darkwebid`) |
| DocuSign envelopes | `scheduled-tasks/docusign/envelopes.task.ps1` | daily | → `docusign_contracts` (standard envelope); GATED — logs+exits until `docusign-token`/`docusign-account-id` provisioned (docs/integrations/docusign.md) |
| UniFi devices | `scheduled-tasks/unifi/devices.task.ps1` | daily | → `unifi_devices`; DOUBLE-GATED — Key Vault `conn-company-unifi` + pending front-end bronze migration (docs/integrations/unifi.md) |
| Plaud recordings | `scheduled-tasks/plaud/recordings.task.ps1` | daily | → `plaud_recordings`; DOUBLE-GATED — `plaud-oauth-token` freshness (fail-loudly re-auth rule) + pending front-end bronze migration (docs/integrations/plaud.md) |
| Kaseya proposals/contracts/tickets | `Invoke-ImperionKaseyaImport` | hourly–daily | bulk upsert, watermarked; Proposals branch delegates to the KQM collector (#98) |
| KQM opportunities | `scheduled-tasks/kqm/opportunities.task.ps1` | daily | → `kqm_opportunities` (quote header, migration 0083); GATED — logs+exits until `kqm-api-key`/Key Vault `KQM-API-Key` reachable; URLs are secret-bearing (?apikey=), never logged; shape verified (spike #427). Won-quote detail = #161 |
| QBO purchases (Check/Expense) | `scheduled-tasks/qbo/purchases.task.ps1` | daily | → `qbo_purchases` (authoritative payment fact, frontend ADR-0082/ADR-0085; backend #105 reads it to set a timesheet Paid). Simple Start has no Accounts Payable, so `Bill`/`BillPayment` are unavailable — the fact re-targets to the `Purchase` entity (#174). GATED — logs+exits until `qbo-access-token`/`qbo-realm-id` provisioned (QBO app reg, the standing time-tracking blocker); the front-end `qbo_purchases` migration (0092, #526) is SHIPPED. Read-only, amount/payee never logged (docs/integrations/quickbooks-online.md, ADR-0014) |
| **Receipt-blob 90-day lifecycle** | `Invoke-ImperionReceiptLifecycle` (the scheduled task passes `-Confirm:$false`) | daily 02:00 | deletes a receipt's storage blob + stamps `receipt_attachment.blob_deleted_at` ONLY when `verified_in_autotask = true` and `uploaded_at` older than 90 days; an aged-but-unverified receipt is RETAINED and flagged (count-only `Warn`), never deleted (frontend ADR-0083, ADR-0015). Idempotent (`-WhatIf`-aware); no PII/paths logged. DOUBLE-GATED — the private storage account + lifecycle (frontend #496) AND migrations 0088–0090 applied (frontend #494, schema live 2026-06-14). Safe deploy-ahead: scans 0 rows on an empty table |
| GDAP relationship health | (build-order task) | hourly | fail-closed surfacing |
| **Gold knowledge + vectorization** | `Invoke-ImperionKnowledgeSync -Vectorize` | nightly 04:30 (after ingests) | composes knowledge_object from silver (incl. FB/IG social interactions — `social` entity type, #127), chunks (v1), embeds via Voyage @ 1024; chunk-hash idempotent — no re-bill (ADR-0009) |
| **OKF semantic drift** | `scheduled-tasks/semantic/drift-sync.task.ps1` (`Invoke-ImperionSemanticDriftSync`) | weekly (after merges) | detects live-silver-vs-OKF-bundle drift (column NAMES only — no data/PII) and PROPOSES a sync against the front-end bundle (#175, frontend ADR-0086). DRY-RUN by default — set `IMPERION_SEMANTIC_DRIFT_EXECUTE=1` + provision `IMPERION_GH_TOKEN` to auto-open (fail-closed: no token → log+exit). Never forks/edits the bundle; humans approve. No bundle/DB → clean no-op (docs/integrations/okf-semantic-drift.md) |

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
