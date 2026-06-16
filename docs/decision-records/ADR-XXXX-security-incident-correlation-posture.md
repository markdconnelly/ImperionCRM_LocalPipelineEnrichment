# ADR-XXXX: Security incidents (MS↔Autotask correlation) + Purview posture + 180-day security retention

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-15 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0005; ADR-0006; ADR-0008; ADR-0010; ADR-0012; ADR-0015; ADR-0018; frontend ADR-0017; frontend ADR-0039; pipeline ADR-0009; pipeline ADR-0018 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as `ADR-XXXX`; the
> orchestrator renames this file to the next free local-pipeline ADR number (next free after
> 0018) at merge and fixes every reference. Do not reserve a number now. The
> `_template.md` placeholder `ADR-NNNN` is untouched.

> **Scope of this ADR is DESIGN ONLY.** The collectors and the retention-sweep cmdlet are the
> **next wave (W30)**. This ADR records the design + decisions; the FE bronze migration it
> depends on (**`0119`**) has **already landed and is prod-applied** — the five physical tables
> exist (verified, see Context). The collector cmdlets ship in the **collector phase of issue
> #196, which stays open**. This repo never creates tables (§5/§6, ADR-0005) — it fails loudly
> on a missing one.

## Problem

Imperion's source catalog (epic #194) does not yet capture the **security-incident picture** —
the day-to-day "what fired, what was it, what did we do about it" of an MSP's security
operations. Two systems hold two faces of the same incident, and neither alone is complete:

- **Microsoft (MDE / Defender XDR / Sentinel)** holds the **security fidelity**: the incident,
  its **alerts** (with MITRE techniques, detection source, severity), and its **evidence**
  (entities, verdicts, remediation status). This is the rich detection payload — but Microsoft
  ages incidents out and is not where the MSP keeps its durable operational history.
- **Autotask** holds the **same incident as a ticket**, and — critically — Autotask is where
  the MSP keeps **long-standing incident history**: it is the **system of record** for the
  incident's existence, lifecycle, and audit trail.

Without stitching these two views the orchestrator agent sees either a rich-but-ephemeral
Microsoft incident **or** a durable-but-thin Autotask ticket, never one normalized incident
timeline. That is a coverage gap (§1: "coverage is the goal; gaps are bugs").

Separately, **Purview** configuration + compliance state is missing from the security-posture
set (Secure Score / CA / Intune / Defender XDR golden-state + drift, ADR-0008) — the posture
picture is incomplete without it.

And ingesting rich security-incident detail (alerts, evidence) into the shared DB indefinitely
is **not wanted**: Autotask already holds the durable history, so the DB only needs a recent
operational window. Without a bound, security rows grow without limit.

## Context

- **Schema is front-end-owned (system CLAUDE.md §1, ADR-0005, frontend ADR-0017).** The physical
  bronze tables are defined by **frontend migration `0119`** — which has **already merged and is
  prod-applied**. This repo is a **producer only**: it writes the migration-defined tables and
  **fails loudly** if one is absent (ADR-0005 §4). No DDL is defined in this ADR.
- **The five tables exist (verified against prod, 2026-06-15).** Confirmed names + envelope:

  | Table | Grain | Key domain columns (beyond the bronze envelope) |
  |---|---|---|
  | `m365_incidents` | incident | `incident_id`, `title`, `severity`, `status`, `classification`, **`autotask_ticket_ref`**, `created_at`, `last_update_at`, `assigned_to` |
  | `m365_alerts` | alert (child of incident) | `alert_id`, **`incident_id`** (FK to incident), `title`, `severity`, `category`, `mitre_techniques`, `detection_source`, `created_at` |
  | `m365_evidence` | evidence (child of alert) | `evidence_id`, **`alert_id`** (FK to alert), `evidence_type`, `entity_value`, `verdict`, `remediation_status` |
  | `purview_compliance_policies` | policy (observed) | `policy_id`, `policy_name`, `policy_type`, `state`, `scope`, `last_modified_at` |
  | `purview_compliance_golden` | policy (golden baseline) | same shape as `_policies` |

  Every table carries the canonical bronze envelope (`tenant_id`, `source`, `external_id`,
  `collected_at`, `raw_payload jsonb`, `content_hash`) per the bronze rule (§5).
- **The correlation key already has a column.** `m365_incidents.autotask_ticket_ref` is the
  Microsoft→Autotask link the FE migration provisioned. Its **exact format is an OPEN ITEM**
  (see Decision §1 and Future considerations) — do **not** invent one; confirm against live data
  in the collector phase.
- **Auth is read-only into client M365.** Issue #196 phrases this as "GDAP read-only"; the
  **live** access model in this repo is the **per-client, admin-consented onboarding app**
  (pipeline ADR-0018, §3) — GDAP is scrapped (CLAUDE.md heads-up). Both mean the same thing
  operationally: **read-only Graph into the client tenant, fail-closed per tenant**. This ADR
  uses the onboarding-app model; "GDAP read-only" in #196 maps to it. The Autotask side reuses
  the **existing Autotask API key** from the SecretStore (already provisioned for
  `autotask_ticket_bronze` / `autotask_contract` — no new secret).
- **Existing posture/drift machinery (ADR-0008/0010).** The `*_policies` + `*_golden` pattern
  and `Get-ImperionPolicyDrift` (compliant / drift / ungoverned / missing) already govern Secure
  Score / CA / Intune / Defender XDR. Purview compliance config slots into that **exact** pattern
  — no new drift mechanism.
- **Retention precedent (ADR-0015).** A gated, logged, `-WhatIf`-aware lifecycle cmdlet that
  deletes only when a durable copy is proven elsewhere is already established (the receipt-blob
  90-day lifecycle, guarded by `verified_in_autotask`). The 180-day security sweep follows that
  idiom.

## Options considered

1. **One ADR for incidents (MS↔Autotask correlation) + Purview posture + the 180-day security
   retention sweep; design-only this phase, collectors + sweep at W30.** *(Chosen.)* The three
   share the security domain, the read-only auth model, and the "Autotask is the durable record,
   the DB is a recent window" framing that motivates the retention bound. Epic #194 splits **by
   domain**, and this **is** the one security domain.
2. One ADR per piece (incidents / Purview / retention separately). Rejected — they are one domain
   and the retention rule exists *because of* the incident-ingestion decision; splitting strands
   the retention rationale from its driver.
3. **Ingest raw security logs** (Azure Firewall / DNS / `AzureDiagnostics`, raw Sentinel tables)
   alongside the curated incidents. **Rejected — explicitly out of scope (epic #194, this issue).**
   KQL hunting stays **native** in Sentinel; we ingest only the **curated** incident / alert /
   evidence payload, never the log stream. A future "add logs" request reopens this ADR rather
   than being treated as a gap.
4. **Ingest Purview alerts** as well as compliance config. **Rejected — Purview alerts explicitly
   NOT ingested** (this issue). Purview enters as **posture only** (config + compliance state),
   joining the golden-state/drift set.
5. **Make Microsoft the system of record** for the incident. **Rejected** — Microsoft ages
   incidents out; **Autotask maintains the long-standing incident history and is the system of
   record**. Microsoft supplies fidelity, not durability.
6. **No retention bound** (keep all security rows forever). Rejected — Autotask already holds the
   durable history, so unbounded retention of rich alert/evidence detail in the shared DB is pure
   cost + PII surface with no benefit. Cap the DB at a recent operational window.
7. Collectors + sweep in this ADR's PR (now). Rejected — this wave is **ADR only**; collectors are
   W30. (Tables already exist, so the gating is scheduling/scope, not a missing migration.)

## Decision

**Adopt the security-incident domain into bronze, design-only this phase; collectors + the
180-day security-retention sweep ship at W30 (collector phase of #196, which stays open).**

### 1. Incidents — correlate Microsoft + Autotask, Autotask is the system of record

Two collectors write the Microsoft side; the Autotask side is **already collected**
(`autotask_ticket_bronze`). Silver stitches them.

- **Microsoft side (read-only Graph via the per-client onboarding app, §3 / pipeline ADR-0018).**
  Pull each tenant's incidents and, for each incident, its alerts, and for each alert, its
  evidence — the security-fidelity payload — into `m365_incidents` / `m365_alerts` /
  `m365_evidence`. Parent→child linkage uses the FE-provisioned columns:
  `m365_alerts.incident_id` → `m365_incidents.incident_id`, and
  `m365_evidence.alert_id` → `m365_alerts.alert_id`. Source key `m365` (the digit-prefix rule:
  digit-led keys get the `m` prefix — `m365`, never `365`, §5). Each follows the canonical
  pattern (§6): pull → flatten to a flat `[PSCustomObject]` table → import to bronze, **upsert
  idempotent on `(tenant_id, source, external_id)`**, skip on unchanged `content_hash`. Bronze
  over-collects every attribute the API exposes into `raw_payload`; silver narrows (§5).
  Security incidents are **operational telemetry, not CRM/operational-config data**, so they
  flatten **straight to Postgres** — the IT Glue documentation step is **skipped** (ADR-0006:
  IT Glue is for the operational-config picture; this isn't that).
- **Autotask side — system of record.** The same incident is an **Autotask ticket**, already in
  `autotask_ticket_bronze`. **Autotask maintains the long-standing incident history and is the
  system of record** for the incident's existence and lifecycle. The DB's Microsoft tables are a
  recent-fidelity overlay; Autotask is durable truth (this is exactly what licenses the 180-day
  cap in §3).
- **Correlation key (OPEN ITEM — do not invent).** The link is
  `m365_incidents.autotask_ticket_ref` ↔ the Autotask ticket identity, and silver stitches the
  two views into **one normalized incident timeline** alongside `interaction` / `ticket`. The
  **exact `autotask_ticket_ref` format is a pending decision** — whether Microsoft carries the
  Autotask **ticket number**, the **ticket id / GUID**, a **URL**, or a tag written by the
  MS↔Autotask sync connector, and how reliably it is populated. **This is flagged for live
  verification in the collector phase** — confirm against real `m365_incidents` rows and the
  Autotask ticket shape before the silver stitch is wired. Until confirmed, the silver join is
  designed but not built. (The reciprocal direction — the Autotask ticket carrying the MS
  incident ref — is verified at the same time.)

### 2. Purview — posture only, into the existing golden-state/drift set

Purview **configuration + compliance state** joins the security-posture set (Secure Score / CA /
Intune / Defender XDR, ADR-0008/0010) via the **identical `*_policies` + `*_golden` pattern**:

- A read-only Graph/Purview pull (per-client onboarding app, read-only) writes observed compliance
  policies to `purview_compliance_policies`; `Set-ImperionPolicyGoldenState` promotes a current
  policy to `purview_compliance_golden` (**human-gated**, as for every golden state, ADR-0008).
- `Get-ImperionPolicyDrift` classifies **compliant / drift / ungoverned / missing** by
  `content_hash` comparison — **no new drift mechanism**, Purview is just another policy family in
  the existing engine, and rolls into the posture silver merge (`Invoke-ImperionPostureMerge`,
  ADR-0010) like the others.
- **Purview ALERTS are explicitly NOT ingested.** Posture (config + compliance state) only.

### 3. Retention — 180-day cap, security rows ONLY

A **gated, logged, scheduled prune cmdlet** — working name **`Invoke-ImperionSecurityRetentionSweep`**
— caps **only** the security-incident rows at **180 days**:

- **Scope is exactly `m365_incidents` / `m365_alerts` / `m365_evidence`** (and is parent→child
  aware: pruning an incident prunes its alerts and their evidence). It does **NOT** touch
  `interaction` bronze, does **NOT** touch the Purview posture tables, and is **NOT** a
  system-wide sweep. Any row whose age (by `created_at` / `collected_at`, exact column confirmed
  in the collector phase) exceeds 180 days is removed.
- **Why 180 days is safe: Autotask holds the durable history** (§1, system of record). The DB
  keeps only a **recent operational window** of high-fidelity Microsoft detail; the long tail
  lives in Autotask. Deleting an aged MS incident row never loses the incident — the Autotask
  ticket persists.
- **Design follows the ADR-0015 retention idiom:** `[CmdletBinding(SupportsShouldProcess)]`,
  `-WhatIf`-aware, **count-only structured logging** (rows scanned / rows pruned per table per
  tenant, no row content in logs), idempotent (a re-run converges — already-pruned rows are
  simply absent), run as the local service account (ADR-0012) on its own scheduled task. Like
  every write path, the actual deletes are **gated** — surfaced before first live run (§8).
- **Implementation is the collector phase (W30)** — this ADR designs it; the cmdlet + its
  scheduled-task registration ship with the collectors.

### 4. Auth, SecretStore, naming

- **Microsoft side: read-only via the per-client onboarding app (§3, pipeline ADR-0018).** The
  cert-backed Entra app authenticates as the consented onboarding app in each client tenant and
  reads that tenant's Graph **read-only**; an unconsented tenant is **never touched** (fail
  closed). #196's "GDAP read-only" maps to this model.
- **Autotask side: the existing Autotask API key** from the SecretStore (already provisioned, no
  new secret). The Purview pull reuses the same onboarding-app Graph path — **no net-new secret**
  is introduced by this ADR. **Secret names only, never values** (§2). If a Purview pull turns
  out to need a distinct scope/app, that is a named, gated addition recorded in the collector
  phase — not invented here.
- **Naming (digit-prefix convention, §5):** the Microsoft source key is `m365` (digit-led → `m`
  prefix). Cmdlet nouns: `SecurityIncident` / `SecurityAlert` / `SecurityEvidence` for the
  collectors, `PurviewCompliance` for the posture pull, and `SecurityRetentionSweep` for the
  prune.

## Consequences

### Security impact

- **Read-only everywhere.** The Microsoft side is **read-only Graph** via the per-client
  onboarding app's minimal granted permission set (§3); the Autotask side is a read-only API pull.
  No write surface back to Microsoft or Autotask. The only write path is into the shared bronze
  tables (and the 180-day prune of those same tables).
- **No secret values anywhere** (system CLAUDE.md §2). Only stable secret **names** are referenced;
  values live in the cert/CMS-unlocked SecretStore (§2). **Never commit secrets.** No new secret
  is introduced (Autotask key + onboarding-app cert already exist).
- **Per-tenant isolation is absolute** (§3) — every incident / alert / evidence / policy row is
  tagged with its owning client tenant; no cross-tenant reads in any query path.
- **180-day retention is itself a security/PII control.** Incident/alert/evidence rows can carry
  sensitive entity detail (hostnames, user identifiers, IPs in evidence). Bounding the DB to a
  180-day window — with Autotask as the durable record — **shrinks the standing PII/exposure
  surface** in the shared store. The prune logs counts only, never row content.
- **Out of scope by decision, not omission:** raw security logs (Firewall/DNS/`AzureDiagnostics`/
  raw Sentinel) and Purview alerts are deliberately **not** ingested — less raw-log PII volume,
  KQL hunting stays native.

### Cost impact

- Negligible ingest cost — scheduled incremental page-walks; idempotent upsert on
  `(tenant_id, source, external_id)` + `content_hash` skip avoids rewriting unchanged rows; no
  embedding cost at the bronze stage.
- The 180-day sweep **reduces** standing storage (and any downstream silver/gold/embed cost) by
  bounding the security row count to a recent window.

### Operational impact

- **FE migration `0119` is already merged + prod-applied** — the five tables exist (verified). So
  unlike sibling #195 (which was gated on `0119` merging), this domain's gate is purely
  **scheduling/scope**: collectors + the retention sweep are the **W30 collector phase of #196**,
  which **stays open**. No `Closes #196` in the ADR PR.
- **Scheduled tasks (registered at the collector phase, §1 one-task-per-(source,entity)):**
  `Imperion-Security-Incidents`, `Imperion-Security-Alerts`, `Imperion-Security-Evidence`,
  `Imperion-Purview-Compliance`, and `Imperion-Security-RetentionSweep` — added to
  `docs/operations/scheduled-task-registry.md` then, run-as the local service account (ADR-0012).
- **Silver consequence (front-end OKF, system CLAUDE.md §11).** Stitching MS + Autotask into one
  normalized **incident** timeline alongside `interaction` / `ticket` is a silver-entity shape /
  source-of-record decision (**Autotask = SoR**). The matching OKF concept file +
  `coverage-matrix.md` row must be proposed back to the front end (file a front-end issue at the
  collector phase, parallel to the schema-ownership rule). Purview compliance extends the existing
  posture concept rather than adding a new entity.
- **Integration + ops docs land in the collector-phase PR** (§9 doc standard):
  `docs/integrations/security-incidents.md` (Graph incident/alert/evidence pull: auth, exact
  onboarding-app permission grants, paging, fields, the `autotask_ticket_ref` correlation note)
  and `docs/integrations/purview-compliance.md`, plus the scheduled-task-registry +
  `docs/database/golden-states-and-drift.md` (Purview added) updates and the retention sweep in
  `docs/operations/`.

## Future considerations

- **Confirm the `autotask_ticket_ref` correlation-key format BEFORE wiring the silver stitch**
  (the OPEN ITEM, §1). Resolve against live data in the collector phase: which Autotask identity
  it carries (number vs id/GUID vs URL vs sync-connector tag), how it's populated (MS↔Autotask
  connector vs manual), reliability, and the reciprocal Autotask→MS ref. This is the
  CONFIRM-BEFORE-LIVE gate for the incident timeline (same posture as the MileIQ / Datto live-shape
  confirmation, ADR-0017 / ADR-0018).
- **Retention threshold is a policy dial.** 180 days is the chosen operational window; if security
  review later wants a different cap (or a per-tenant override), it is a config change to the sweep,
  not a schema change.
- **Incident timeline → gold / embeddings.** Once the silver incident timeline lands, the
  normalized incident narrative is a natural gold knowledge object for the orchestrator (§7) — a
  follow-up once bronze + silver are flowing.
- **Reopen, don't treat as a gap:** a future "add raw security logs" or "add Purview alerts"
  request **reopens this ADR** rather than being a coverage bug (epic #194 exclusion discipline).

## Cross-references

ADR-0005 (source catalog & table naming; fail-loud-on-missing-table; digit-prefix `m365`) ·
ADR-0006 (IT Glue documentation hub — and the operational-config-vs-other split that sends security
incidents straight to Postgres) · ADR-0008 (golden states + drift — the `*_policies`/`*_golden` +
`Get-ImperionPolicyDrift` pattern Purview joins) · ADR-0010 (posture silver bulk merge Purview rolls
into) · ADR-0012 (local service-account run-as identity) · ADR-0015 (gated, `-WhatIf`-aware,
count-only retention-lifecycle idiom the 180-day sweep follows) · ADR-0018 (per-client onboarding-app
read-only access — the live "GDAP read-only" model) · frontend ADR-0017 (schema ownership —
migrations are front-end-owned; `0119` defines these tables) · frontend ADR-0039 (per-source bronze) ·
pipeline ADR-0009 (per-source bronze) · pipeline ADR-0018 (per-client onboarding app — access
mechanics source of truth). Issues: **#194** (epic — source-catalog expansion, split by domain),
**#196** (this child — **ADR phase here; collectors + the retention sweep follow at W30**; stays
open), **frontend (migration `0119`** — security bronze tables, already merged + prod-applied),
**#195** (sibling — RMM/managed-estate domain).
