# Collector inventory

The single map of **every collector** in the `ImperionPipeline` module: source →
connect/get/post cmdlets → scheduled task → bronze target → cadence → governing ADR. It is
the onboarding entry point for "what does this pipeline ingest, and how."

> **How to read this.** Each source area lives under `src/ImperionPipeline/Public/<area>/`
> split into `connect/` (reusable auth + paged request), `get/` (flatten the source JSON to a
> bronze-shaped `[PSCustomObject]` table — no writes), and `post/` (`Set-Imperion*ToBronze`,
> the change-detected upsert). A short `scheduled-tasks/<area>/<entity>.task.ps1` composes
> get → post and is registered with `Register-ImperionTask`. The **cadence** column is the
> target; tune per source rate-limits in [`integrations/<source>.md`](integrations/). Physical
> bronze table names are **defined by the front-end migration** (front-end ADR-0017); this repo
> fails loudly on a missing table. ADR numbers are this repo's unless prefixed.

The **as-built registry of registered tasks, with full gating notes**, is
[`operations/scheduled-task-registry.md`](operations/scheduled-task-registry.md). This page is
the higher-altitude catalog.

## CRM / sales

| Source | Connect | Get (collector) | Bronze target | Cadence | ADR / issue |
| --- | --- | --- | --- | --- | --- |
| **Autotask** | `Invoke-ImperionAutotaskRequest` (+ `Get-ImperionAutotaskZone`) | Company · Contact · Contract · Ticket · TimeEntry | `autotask_*` (contracts/tickets standard envelope; time entries ADR-0082) | companies/contacts/contracts daily · tickets 15–30 min · time entries hourly | ADR-0005 |
| **IT Glue** | `Invoke-ImperionITGlueRequest` | Organization · Contact · Configuration (= devices) · full Export | `itglue_companies` / `itglue_contacts` / `itglue_devices` (ADR-0039 shape) + `itglue_export_*` + `itglue_export_relationship` | daily | ADR-0006 |
| **KQM (Kaseya Quote Manager)** | `Invoke-ImperionKqmRequest` | Opportunity (header) → OpportunityDetail (won-quote sections/lines) | `kqm_opportunities` (migration 0083) | daily | #160 / #161 |
| **DocuSign** | `Invoke-ImperionDocuSignRequest` | Envelope (contracts) | `docusign_contracts` | daily | ADR-0005 |
| **Meta (FB / IG)** | `Invoke-ImperionMetaRequest` (+ `Get-ImperionMetaPageToken`) | Page posts/comments/conversations/insights · IG media/comments (+ `Invoke-ImperionMetaMerge`) | `meta_*` / `instagram_*` (migration 0075) | daily | ADR-0013 / #126 |
| **Kaseya (legacy bulk)** | — | `Invoke-ImperionKaseyaImport` (contracts/tickets/proposals; Proposals branch delegates to KQM) | bulk upsert, watermarked | hourly–daily | #98 |

## Support / operational (RMM / managed estate)

| Source | Connect | Get (collector) | Bronze target | Cadence | ADR / issue |
| --- | --- | --- | --- | --- | --- |
| **Datto RMM** | `Invoke-ImperionDattoRmmRequest` (API-key → short-lived bearer exchange) | Device (patch/AV state, asset/software inventory) | `datto_rmm_devices` (migration 0119) | daily | ADR-0018 / #195 |
| **Datto BCDR** | `Invoke-ImperionDattoBcdrRequest` (Bearer) | Backup (per-device backup posture, joins `device_uid`) | `datto_bcdr_backups` (migration 0119) | daily | ADR-0018 / #195 |
| **myITprocess** | `Invoke-ImperionMyItProcessRequest` (`api_token` header) | Recommendation (vCIO roadmap/QBR → account) | `myitprocess_recommendations` (migration 0119; straight to Postgres, skips IT Glue) | daily | ADR-0018 / #195 |
| **UniFi** | `Invoke-ImperionUniFiRequest` (one **company** Site Manager key enumerates all sites, #321/#345) | Device (+ config compliance), per site | `unifi_devices` (FE migration `0162` applied; 16 live) → silver `device` **merged on-prem** by `Invoke-ImperionUniFiMerge` (#284/#317) | daily | ADR-0018 / ADR-0026 |
| **Pax8** | `Invoke-ImperionPax8Request` (company creds via registry → KV, ADR-0029) | Company · Subscription · Order (`/v1/licenses` 404 — dropped, #338) | `pax8_companies` / `pax8_subscriptions` / `pax8_orders` (#279/#290; 8/12/73 live) → silver `license_assignment` **merged on-prem** by `Invoke-ImperionPax8Merge` (#280/#314, #316) | daily | #279 / ADR-0026 |
| **Plaud** | `Invoke-ImperionPlaudRequest` (per-user OAuth) | Recording (note + transcript) | `plaud_recordings` (pending FE migration) | daily | ADR-0005 |

## Microsoft 365 / Entra / Azure (per-client onboarding app, read-only — ADR-0018)

| Source | Connect | Get (collector) | Bronze target | Cadence | ADR / issue |
| --- | --- | --- | --- | --- | --- |
| **m365 directory** | `Invoke-ImperionGraphRequest` | User · Device · Group · GroupMember | `m365_contacts` / `m365_devices` / `m365_groups` / `m365_group_members` (ADR-0039 shape) → silver `contact_enrichment.directory_groups` **merged on-prem** by `Invoke-ImperionM365DirectoryMerge` (#239; cloud cede Pipeline #134 held until bronze fills) | daily | ADR-0005 / ADR-0026 |
| **m365 Intune** | `Invoke-ImperionGraphRequest` | Managed device compliance · Managed app | `intune_managed_devices` / `intune_managed_apps` (pending FE migration) | daily | #75 / #143 |
| **m365 communications (cross-org)** | `Invoke-ImperionGraphRequest` | Mail · TeamsChat · TeamsMeeting (Imperion↔client filter) | `m365_mail_messages` / `m365_teams_chats` / `m365_teams_meetings` (migration 0065) | mail/chat hourly · meetings 4h | #100 |
| **Entra hygiene** | `Invoke-ImperionGraphRequest` | Domain · AppRegistration · RoleAssignment · Group · GroupMember · AuthMethod | `entra_domains` / `entra_app_registrations` / `entra_role_assignments` / `entra_groups` / `entra_role*` (migrations 0136/0079/0077, all prod-applied) | daily | #219/#139–#142 / #150 |
| **Information protection** | `Invoke-ImperionGraphRequest` | SensitivityLabel (beta) · CustomSecurityAttribute (definitions only) | `m365_sensitivity_labels` / `entra_custom_security_attributes` (FE #575, applied) | daily | #141/#372 |
| **m365 SharePoint** | `Invoke-ImperionGraphRequest` | SharePointSite (metadata only — no file content) | `sharepoint_sites` (migration 0078) | daily | #137 |
| **Azure ARM** | `Invoke-ImperionArmRequest` | Subscription · ResourceGroup · Resource · DNS zone/resolve · Sentinel | `azure_*` (migrations 0038/0043) · `sentinel_*` · DNS set (ADR-0063) | daily | ADR-0005 |
| **Azure ARM cloud-asset (CMDB, per-client)** | `Invoke-ImperionArmRequest` | `Get-ImperionCloudResource` (Subscription · ResourceGroup · Resource, **fanned out from silver `account_tenant`** #234) | `cloud_subscriptions` / `cloud_resource_groups` / `cloud_resources` (FE migration 0130 applied; tags emit as `jsonb` #237) → silver `cloud_asset` **merged on-prem** by `Invoke-ImperionCloudAssetMerge` (#241; cloud ceded `mergeCloudAssetSources`, Pipeline #135) | daily | ADR-0023 / ADR-0026 / #201, #216 |

## Security posture (read-only Graph / ARM)

| Source | Cmdlet | Bronze / output | Cadence | ADR / issue |
| --- | --- | --- | --- | --- |
| **Service principals** | `Invoke-ImperionServicePrincipalSync` | SPs → IT Glue + Postgres (credential-expiry watch) | daily | ADR-0008 |
| **Azure + Sentinel inventory** | `Invoke-ImperionAzureInventorySync` | mgmt-groups/subs/RGs/resources + Sentinel | daily | ADR-0008 |
| **Secure Score** | `Invoke-ImperionSecureScoreSync` | `secure_scores` + control profiles | daily | ADR-0008 |
| **Posture policies + drift** | `Invoke-ImperionPolicySync` (+ `Get-ImperionPolicyDrift` / `Set-ImperionPolicyGoldenState`) | CA / Intune / device-config / Autopilot / Defender XDR policies + `*_golden` | daily | ADR-0008 |
| **Posture silver merge** | `Invoke-ImperionPostureMerge` | classify `posture_policy` + roll up `tenant_posture` | daily 03:20 | ADR-0010 |
| **Posture snapshots** | `Invoke-ImperionPostureSnapshot` | immutable `posture_snapshot` per account (Imperion Secure Score, quarterly self-gate) | daily 03:40 | ADR-0011 |
| **Security incidents** | `Get-ImperionSecurityIncident` → `Set-ImperionSecurityIncidentToBronze` | `m365_incidents` / `m365_alerts` / `m365_evidence` (+ `autotask_ticket_ref`) | hourly | ADR-0019 / #196 |
| **Purview compliance** | `Invoke-ImperionPurviewComplianceSync` | `purview_compliance_policies` + `_golden` drift (NO alerts) | daily | ADR-0019 / #196 |
| **Security retention sweep** | `Invoke-ImperionSecurityRetentionSweep` | 180-day prune of incidents/alerts/evidence ONLY | daily | ADR-0019 §3 |
| **Dark Web ID** | `Invoke-ImperionDarkWebIdRequest` (Basic auth — `username`+`password` from the credential registry blob, #348/#349) → `Set-ImperionDarkWebIdCompromiseToBronze` | `darkwebid_exposures` (ADR-0039 shape) | daily | ADR-0005 / ADR-0029 |
| **Telivy** | `Invoke-ImperionTelivyRequest` → `Set-ImperionTelivyReportToBronze` | `televy_reports` (ADR-0039 shape; source `televy`) | daily | ADR-0005 |
| **EasyDMARC** | `Invoke-ImperionEasyDmarcRequest` | `easydmarc_domains` (DMARC/SPF/DKIM/BIMI; pending FE migration) | daily | #122 |
| **DNS posture** | `Get-ImperionDnsZoneObject` / `Get-ImperionDnsResolveObject` → `Invoke-ImperionDnsMerge` | DNS zones + public resolve + golden/drift → `dns_domain` | daily | ADR-0063 (FE) |
| **Defender XDR (m365)** | `Get-ImperionDefenderObject` → `Set-ImperionDefenderToBronze` | `defender_xdr_*` (migration 0076) | hourly | #138 |

## Finance / BI (QuickBooks Online + MileIQ)

All QBO collectors share one connection (`Invoke-ImperionQboRequest`) — one app reg, many
readers. Read-only; financial amounts / customer PII are **never logged** (counts only). All
gated on `qbo-access-token` / `qbo-realm-id` (the standing QBO app-reg blocker).

| Source | Get | Bronze target | Cadence | ADR / issue |
| --- | --- | --- | --- | --- |
| **QBO invoices** | `Get-ImperionQboInvoice` | `qbo_invoices` (revenue / A/R) | daily | ADR-0020 / #197 |
| **QBO payments** | `Get-ImperionQboPayment` | `qbo_payments` (customer cash in) | daily | ADR-0020 / #197 |
| **QBO customers** | `Get-ImperionQboCustomer` | `qbo_customers` | daily | ADR-0020 / #197 |
| **QBO estimates** | `Get-ImperionQboEstimate` | `qbo_estimates` | daily | ADR-0020 / #197 |
| **QBO bills (A/P)** | `Get-ImperionQboBill` | `qbo_bills` (graceful-degrades on Simple Start) | daily | ADR-0020 / #197 |
| **QBO chart of accounts (full)** | `Get-ImperionQboAccount` | `qbo_accounts` | daily | ADR-0020 / #197 |
| **QBO chart of accounts (expense)** | `Get-ImperionQboExpenseAccount` | `qbo_expense_account` (category SoR) | daily | ADR-0083 (FE) |
| **QBO P&L snapshot** | `Get-ImperionQboProfitAndLoss` | `qbo_profit_and_loss` (one snapshot row per period) | daily/monthly | ADR-0020 / #197 |
| **QBO purchases** | `Get-ImperionQboPurchase` | `qbo_purchases` (payment fact, migration 0092) | daily | ADR-0014 |
| **MileIQ** | `Get-ImperionMileIqDrive` (per-employee OAuth; backend custodies the token) | `mileiq_drives` (business-only; migrations 0088–0090) | daily | ADR-0017 |

## Logistics / procurement (read-only — no order is ever placed)

| Source | Connect | Get | Bronze target | Cadence | ADR / issue |
| --- | --- | --- | --- | --- | --- |
| **Amazon Business** | `Invoke-ImperionAmazonBusinessRequest` (Bearer; `nextToken` paging) | Order (+ shipment/tracking + spend) | `amazon_business_orders` (migration 0120; straight to Postgres) | daily | ADR-0021 / #198 |
| **CDW** | `Invoke-ImperionCdwRequest` (Bearer; `?page=N`) | Order (+ PO + shipment/tracking + spend) | `cdw_orders` (migration 0120; straight to Postgres) | daily | ADR-0021 / #198 |

## Scoped interaction (ADR-0022 — message-grain, scoped at collection)

Only allowlisted-principal (`%ProgramData%\Imperion\interaction-allowlist.json`) ↔ client
(silver `contact`/`account`) messages land; internal-only and non-client are dropped (lawful
basis). Read-only Graph via the cert SP; subjects/addresses **never logged** (counts only).
DORMANT until the allowlist + consent.

| Source | Get | Bronze target | Cadence | ADR / issue |
| --- | --- | --- | --- | --- |
| **Scoped mail** | `Get-ImperionScopedInteractionMail` → `Set-ImperionScopedInteractionMailToBronze` | `m365_email` (migration 0120, source `m365_email`) | hourly | ADR-0022 / #199 |
| **Scoped Teams** | `Get-ImperionScopedInteractionTeams` → `Set-ImperionScopedInteractionTeamsToBronze` | `m365_teams` (migration 0120, source `m365_teams`) | hourly | ADR-0022 / #199 |

## Bronze→silver merge (LP-owned — ADR-0026, "merge co-locates with ingestion")

Whichever plane *ingests* a source's bronze owns its bronze→silver merge. This repo owns the
merge for every source it bulk-ingests — an idempotent, set-based `Invoke-Imperion*Merge` cmdlet
run by a `.task.ps1` immediately after that source's collectors. The cloud Pipeline keeps only
the live/webhook-driven merge (the `website_*`-fed contact/account/device/contract/ticket/
opportunity/expense sweep + DocuSign).

| Merge | Cmdlet | Silver target | Cadence | ADR / issue |
| --- | --- | --- | --- | --- |
| **Posture** (the precedent) | `Invoke-ImperionPostureMerge` | `posture_policy` + `tenant_posture` | daily 03:20 | ADR-0010 |
| **DNS** | `Invoke-ImperionDnsMerge` | `dns_domain` (golden/drift) | daily | ADR-0008 / ADR-0063 (FE) |
| **Meta** | `Invoke-ImperionMetaMerge` | social interaction silver | daily | ADR-0013 |
| **M365 directory** | `Invoke-ImperionM365DirectoryMerge` | `contact_enrichment.directory_groups` (FE migration 0079) | daily | ADR-0026 / #239 |
| **Azure ARM cloud-asset** | `Invoke-ImperionCloudAssetMerge` | `cloud_asset` CMDB CI (FE migration 0139; cloud ceded #135; 101 live) | daily | ADR-0026 / #241 |
| **UniFi** | `Invoke-ImperionUniFiMerge` | `device` (from `unifi_devices` bronze; per-site attribution defect #346) | daily | ADR-0026 / #284 |
| **Pax8** | `Invoke-ImperionPax8Merge` | `license_assignment` (resolves company → account via `entity_xref`; agreement/device link) | daily | ADR-0026 / #280 |

> **Cutover is gap-free** because both the LP and cloud copies are replace-from-source on the
> same source label: ship the LP merge first (additive), cede the cloud copy second, never cede
> before the LP copy is verified writing in prod.

## Gold knowledge + vectorization (ADR-0009 — LIVE)

| Stage | Cmdlet | Output |
| --- | --- | --- |
| **Compose** | `Get-ImperionKnowledge*` (account · contact · contract · ticket · device · exposure · assessment · proposal · posture · social · conversation_segment) → `Set-ImperionKnowledgeObject` | `knowledge_object` (change-detected) |
| **Chunk** | `Split-ImperionTextChunk` (v1: 6000 chars / 500 overlap) | text chunks |
| **Embed** | `Get-ImperionVoyageEmbedding` (voyage-3-large @ 1024, refuses other dims) | 1024-dim vectors |
| **Upsert** | `Invoke-ImperionVectorizeKnowledge` (chunk-hash idempotent, cost telemetry) | `knowledge_embedding` (pgvector) |
| **Entry point** | `Invoke-ImperionKnowledgeSync [-Vectorize]` | nightly `Imperion-KnowledgeVectorize` (04:30) |

See [vectorization-to-gold.md](vectorization-to-gold.md) and
[database/vector-lifecycle.md](database/vector-lifecycle.md).

## Semantic-layer drift (front-end ADR-0086, #175)

| Stage | Cmdlet | Output |
| --- | --- | --- |
| **Detect + propose** | `Invoke-ImperionSemanticDriftSync` (`Get-ImperionSemanticDrift`) | live-silver-vs-OKF-bundle drift (column **names** only) → proposed PR against the FE bundle (dry-run default; humans approve) |

---

> **Coverage is the goal; gaps are bugs** (`CLAUDE.md §1`). A new source is one connect + one
> get + one post adapter (over `Invoke-ImperionBronzePost`) + one task file + one row here. A
> new gold entity is one composer (over `Invoke-ImperionKnowledgeCompose`) + one line in
> `Invoke-ImperionKnowledgeSync`.
