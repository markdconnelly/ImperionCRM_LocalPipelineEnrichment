# ADR-0023: Azure ARM cloud-resource inventory — per-client cloud-asset bronze (CMDB CI source)

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-17 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0005; ADR-0012; ADR-0018; frontend ADR-0017; frontend ADR-0039; frontend ADR-0078; pipeline ADR-0018 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as `ADR-0023`; the
> orchestrator renames this file to the next free local-pipeline ADR number at merge and
> fixes every reference. Do not reserve a number now.

> **Scope of this ADR + its slice-1 collector.** This is **slice 1 of epic #201**: the ADR
> (design) **and** the per-client ARM resource-inventory **bronze** collector. The collector
> is **gated on a front-end bronze migration** (the `cloud_resource*` tables, filed as a
> front-end issue — the schema dependency referenced from this PR), which is **not merged
> yet**. The collector merges **dormant**: it fails loudly on the missing table and the task
> file's catch logs a Warn and exits cleanly, exactly like the DNS-posture collector while it
> waited on front-end `0080` (`azure/dns-zones`, #155). This repo never creates tables
> (§5/§6, ADR-0005) — it fails loudly on a missing one. Silver `cloud_asset` + the CMDB CI
> stitch are **later slices** of #201, out of scope here.

## Problem

Imperion's CMDB (front-end #372, ADR-0078) defines a **cloud-asset CI type**, but no
ingestion source backs it. The existing Azure inventory (`Invoke-ImperionAzureInventorySync`
/ `Get-ImperionAzureResource` → `azure_resources`, ADR-0008 / migration 0038) enumerates the
resources of **Imperion's own (partner) tenant** for security posture — it authenticates
against `PartnerTenantId` and is not tenant-fanned-out, account-scoped, or shaped to feed the
CMDB. There is therefore **no per-managed-client cloud-resource picture** (each customer's
subscriptions, resource groups, VMs, storage, app services, SQL, networking, …) that the
CMDB can register as cloud-asset CIs and relate to the owning account (and, where derivable,
to devices). Coverage is the goal; gaps are bugs (§1) — this is the gap.

## Context

- **Schema is front-end-owned (system CLAUDE.md §1, ADR-0005).** The physical bronze tables
  for this source are defined by a **front-end migration** (filed as a front-end issue, the
  schema dependency of slice 1), not here. This repo is a **producer only**: it writes the
  migration-defined tables and **fails loudly** if one is absent (ADR-0005 §4). No DDL is
  defined in this ADR.
- **This is NOT the existing `azure_resources` set.** That set is the **partner-tenant,
  posture-scoped** inventory (ADR-0008, migration 0038): one tenant, no account scoping, a
  security view. This source is **per-managed-client, CMDB-scoped**: fanned out across the
  consented client tenants (§3), every row carries the owning customer tenant, and the flat
  shape is chosen for the CMDB cloud-asset CI (account-relatable). The two coexist by design
  and write **different tables**; silver narrows/dedupes downstream. New tables (`cloud_*`)
  avoid overloading the posture set's meaning.
- **Auth is the per-client onboarding-app cert-SP ARM token, Reader (§3, pipeline ADR-0018,
  ADR-0018).** GDAP is scrapped; client Azure/ARM is reached as the consented onboarding app
  in each client tenant via the cert-backed Entra app (`Get-ImperionArmToken -TenantId
  <client>`, resource `https://management.azure.com/.default`, **Reader** — already the
  posture set's grant, **no new write grant**). Fail closed: a tenant with no consent /
  credential pair is never reached. Per-tenant isolation is absolute — every row is stamped
  with its owning customer tenant; no cross-tenant reads.
- **Device / cloud-asset precedence (front-end ADR-0039 resurrection guard).** The silver
  `device` merge is recomputed by precedence with manual `website_*` highest (the
  resurrection guard) and machine sources below. Where a cloud resource maps to a device
  (e.g. an ARM VM ↔ an Intune/RMM-known machine), this source slots into the **machine tier,
  below `website`** — never overriding a manual entry. But a cloud **resource** is mostly a
  *new* CI class (storage account, app service, SQL DB) with no device counterpart; for those
  it is the sole source. Exact precedence among machine sources is a silver-slice decision
  (later #201 slice + a front-end OKF/`coverage-matrix` update, system §11); slice 1 only
  lands bronze and records the guard.
- **Retention.** Cloud-resource bronze is **operational infrastructure inventory**, not the
  180-day-retention security-incident class (that is sibling #196 / ADR-0019). It follows the
  **standard idempotent change-detected upsert** (no scheduled purge) — current-state
  inventory, re-collected on cadence, unchanged rows not rewritten. A 180-day window is **out
  of scope** here; if a point-in-time history is later wanted it is a separate decision.

## Options considered

1. **New per-client `cloud_resource*` bronze + a CMDB-shaped collector, gated on a new
   front-end migration; reuse the `Get-/Set-…ToBronze` get/post pattern and the existing ARM
   connect layer.** *(Chosen.)* Keeps the posture inventory untouched, gives the CMDB its own
   account-scoped source, fans out per client tenant, and ships as ~15-line adapters over the
   shared scaffold.
2. **Reuse `azure_resources` (the posture set) for the CMDB too.** Rejected — it is
   partner-tenant + posture-scoped (ADR-0008); overloading it with per-client CMDB rows
   conflates two meanings (a silver/OKF hazard) and forces account scoping onto a table that
   was not designed for it.
3. **Collector in a later slice (ADR design-only now).** Rejected — the collector is small,
   self-contained, and dormant-safe; shipping it with the ADR (gated on the FE migration) is
   the same proven shape as the DNS-posture collector that waited on `0080`. Design + build
   together; it simply runs no-op until the table exists.
4. **Enumerate every managed-client subscription from the partner tenant (single auth).**
   Rejected — client subscriptions live in the client tenants; the access model is the
   per-client onboarding app (§3, pipeline ADR-0018), so auth fans out per tenant and fails
   closed per tenant.

## Decision

**Adopt a per-client Azure ARM cloud-resource inventory as a new CMDB cloud-asset bronze
source. Ship slice 1 = this ADR + the bronze collector (get/post + scheduled task), gated on
a new front-end `cloud_resource*` migration; dormant (fail-loud) until that migration lands.**

### 1. Source, bronze tables, grain

The **physical table names are owned by the front-end migration** (filed as the front-end
issue this PR references). This ADR references them by name; the collector fails loudly if
absent — it does **not** define their DDL.

| Source key | Bronze table (front-end migration) | Grain | Account relation |
|---|---|---|---|
| `azure_arm` | `cloud_subscriptions` | subscription (per client tenant) | tenant ⇒ account |
| `azure_arm` | `cloud_resource_groups` | resource group | via subscription |
| `azure_arm` | `cloud_resources` | resource (VM / storage / app service / SQL / networking / …) | via subscription + (where derivable) device |

Each follows the canonical pattern (§6): per-client ARM token (Reader) → page
`/subscriptions`, then per subscription `/resourcegroups` and `/resources` → flatten to the
standard flat-table envelope (`tenant_id`, `source`, `external_id`, `collected_at`,
`raw_payload`, `content_hash` + flat columns) → upsert idempotent on
`(tenant_id, source, external_id)` with change detection. Bronze over-collects (the full ARM
object is lossless in `raw_payload`); the flat columns are the CMDB-queryable subset. Each
writer is a thin `-ColumnSet` adapter over `Invoke-ImperionBronzePost` (issue #105 scaffold)
— a future collector field can never break the insert (extras survive in `raw_payload`).

The slice-1 collector lands **resources** (the cloud-asset CIs) + the **subscription /
resource-group context** that scopes them. `external_id` is the ARM **resource id** (the
stable, globally-unique ARM path) for resources, the `subscriptionId` for subscriptions, and
the RG ARM id for resource groups.

### 2. Auth, tenant fan-out, isolation

- **Auth:** `Get-ImperionArmToken -TenantId <clientTenant>` — the cert-SP app-only ARM token
  in the target client tenant (pipeline ADR-0018 onboarding-app model), resource
  `https://management.azure.com/.default`, **Reader** (already held; **no new grant**).
- **Tenant fan-out:** the scheduled task iterates the consented client tenants (the
  `IMPERION_M365_TENANT_IDS` env list, the same fan-out idiom the `m365/*` tasks use; an
  empty list ⇒ partner-tenant-only, dormant-safe). The collector takes an optional
  `-TenantId` (defaults to the partner tenant) and is called once per tenant.
- **Per-tenant isolation:** every flattened row is stamped `tenant_id = <the tenant
  authenticated against>` (`ConvertTo-ImperionFlatObject -TenantId`). No query reads across
  tenants. A tenant with no consent / credential pair throws on token acquisition; the task's
  per-tenant catch logs and continues (fail closed, never silently mis-attribute).

### 3. Dormant-safe gating

The collector + task are merged **dormant**:

- **Schema gate.** Until the front-end `cloud_*` migration is applied to prod, the post-layer
  upsert fails loudly (the table is absent — ADR-0005 fail-loud). The task file wraps the run
  in a `try/catch` that logs a Warn (`Write-ImperionLog -Level Warn`) and exits cleanly, so
  the schedule never crashes — identical to `azure/dns-zones.task.ps1` pre-`0080`.
- **Identity / consent gate.** With no consented client tenants configured
  (`IMPERION_M365_TENANT_IDS` empty), the task falls back to the partner tenant only — and if
  the cert-SP context is not initialized, `Initialize-ImperionContext` / token acquisition
  fails loudly and the same catch exits clean. No SecretStore / onboarding-app config ⇒ no-op
  + log, never a crash (the retire-`-SkipSecretStore` dormant posture).

### 4. Naming + connect layer

- **Source key `azure_arm`** (digit-prefix convention §5: no leading digit, spelled out;
  distinct from the posture `azure` key so the CMDB source is unambiguous in
  `coverage-matrix` / OKF).
- **Cmdlets:** get `Get-ImperionCloudResource`, post `Set-ImperionCloudResourceToBronze`
  (multi-table router by `entity` discriminator: `subscriptions` / `resource_groups` /
  `resources`, mirroring `Set-ImperionDnsZoneToBronze`). They live under the existing
  `Public/azure/` area and reuse the existing `Invoke-ImperionArmRequest` connect helper +
  `Get-ImperionArmToken` — **no new connect layer, no new secret**.
- **Scheduled task:** `scheduled-tasks/azure/cloud-resources.task.ps1` — Daily; composes the
  get → post per tenant; registered at server bringup (deferred, like the rest, to #102).

## Consequences

### Security impact

- **No new grant, no new secret.** Reuses the cert-SP ARM **Reader** token (already held) and
  the per-client onboarding-app model (§3). **Never commit secrets** (system §2) — none are
  introduced; the ARM token rides the `Authorization` header, never a querystring or a log.
- **Read-only.** Pure ARM GETs — no write surface back to any client's Azure. No IT Glue write
  surface added (cloud resources are CMDB-bound, not the IT Glue documentation path here).
- **Per-tenant isolation + fail-closed** (§3): every row carries its owning client tenant; an
  unconsented tenant is never reached. Cloud-resource metadata is operational, not comms-PII;
  standard tenant-tagging applies.
- **No 180-day retention concern** (that is the security-incident class, #196) — this is
  current-state inventory under the idempotent change-detected upsert.

### Cost impact

- Negligible. Scheduled daily page-walks per client subscription; idempotent change-detected
  upsert on `(tenant_id, source, external_id)` skips rewriting unchanged rows; no embedding
  cost at the bronze stage.

### Operational impact

- **Gated on the front-end `cloud_*` migration** (the front-end issue this PR references).
  The collector runs live only once that migration is merged + applied; until then it is
  dormant (fail-loud → task catch logs + exits clean).
- **One scheduled task** — `azure/cloud-resources` (Daily) — registered in
  `docs/operations/scheduled-task-registry.md` at server bringup (#102), run-as the local
  service account (ADR-0012). Listed in `docs/collector-inventory.md` (Azure ARM section).
- **Front-end follow-up (silver + OKF/CMDB), later #201 slices:** the silver `cloud_asset`
  shape, the CMDB cloud-asset CI stitch (relate to account + device, front-end ADR-0078), and
  the device-merge precedence note must update the front-end OKF concept file +
  `coverage-matrix.md` (system §11) — filed in the front end when those slices land (propose
  in the front end, like a schema change).
- **Integration doc** (`docs/integrations/azure-arm-cloud-inventory.md`: auth, endpoints,
  cadence, fields, paging, retry, the CONFIRM-BEFORE-LIVE list) ships in this PR (§9).

## Future considerations

- **Cloud resource ↔ device join.** Where an ARM VM maps to an Intune/RMM-known machine, the
  silver merge relates the cloud-asset CI to the device CI (front-end ADR-0078 relationships)
  — a silver-slice decision (precedence per ADR-0039: below `website`).
- **Cost / tag governance signals.** ARM resource tags + SKU could feed a future cost or
  tag-hygiene posture (a `cloud_*_golden` golden-state, ADR-0008-style) — a later ADR.
- **Confirm live shapes before LIVE.** The exact per-tenant subscription visibility, ARM
  api-versions, and which resource fields the CMDB wants are confirmed against real client
  tenants in the live-bringup step (the CONFIRM-BEFORE-LIVE list in the integration doc), the
  same precedent as the DNS-posture and security-incident collectors.

## Cross-references

ADR-0005 (source catalog & table naming; fail-loud-on-missing-table) · ADR-0008 (the
**partner-tenant** Azure/Sentinel posture inventory this is distinct from) · ADR-0012 (local
service-account run-as identity) · ADR-0018 (per-client onboarding-app access; the auth
model) · frontend ADR-0017 (schema ownership — migrations are front-end-owned) · frontend
ADR-0039 (per-source bronze + `website` resurrection guard — the device/cloud-asset
precedence anchor) · frontend ADR-0078 (CMDB + cloud-asset CI type — the consumer) · pipeline
ADR-0018 (onboarding-app mechanics). Issues: **#201** (epic — Azure ARM cloud-resource
inventory), **#216** (this child — slice 1: ADR + per-client resource bronze collector),
**front-end `cloud_resource*` bronze migration** (the schema dependency, filed in the front
end), **front-end #372** (CMDB cloud-asset CI slice — blocked-by #201).
