# Azure ARM cloud-resource inventory — per-client CMDB cloud-asset source

**Epic:** local #201 · **Issue:** local #216 (slice 1) · **Decision:** ADR-XXXX (this repo) ·
**Schema:** front-end `cloud_resource*` migration (the schema dependency — filed as a
front-end issue, **not merged yet**) · **Source key:** `azure_arm`

## Purpose

The per-managed-**client** Azure Resource Manager (ARM) resource inventory that backs the
**cloud-asset CI type** in the front-end CMDB (front-end #372 / ADR-0078). Enumerates each
consented client tenant's subscriptions, resource groups, and resources (VMs, storage, app
services, SQL, networking, …) and lands them in the new per-client `cloud_*` bronze set.

**Distinct from the partner-tenant posture inventory** (`azure/inventory`,
`Get-ImperionAzureResource` → `azure_resources`, ADR-0008 / migration 0038): that set is one
tenant (Imperion's own), security-scoped, not account-scoped. **This** source is
per-client, CMDB-shaped, fanned out across client tenants, and account-relatable. The two
coexist by design and write different tables.

## Pipeline

| | |
|---|---|
| **Get** | `Get-ImperionCloudResource [-TenantId <client>] [-ApiVersion 2022-09-01]` |
| **Post** | `Set-ImperionCloudResourceToBronze` (multi-table router by `entity`) |
| **Tables** | `cloud_subscriptions` (entity `subscriptions`), `cloud_resource_groups` (entity `resource_groups`), `cloud_resources` (entity `resources`) |
| **Task** | `scheduled-tasks/azure/cloud-resources.task.ps1` — **Daily** |

Each subscription yields one `cloud_subscriptions` row (`display_name`, `state`,
`sub_tenant_id`), one `cloud_resource_groups` row per RG (`name`, `location`,
`subscription_id`, `provisioning_state`, `tags`), and one `cloud_resources` row per resource
(`name`, `type`, `location`, `kind`, `sku`, `resource_group`, `subscription_id`, `tags`).
Standard bronze envelope, PK `(tenant_id, source, external_id)`, change-detected. `external_id`
= the ARM **resource id** for resources / the RG ARM id for resource groups / the
`subscriptionId` for subscriptions. The full ARM object is lossless in `raw_payload`; flat
columns are the CMDB-queryable subset.

## Auth & permissions

Cert-SP ARM token (`https://management.azure.com/.default`), **Reader** — already held,
**no new grant**. Reached **per client tenant** via the per-client onboarding-app model
(`Get-ImperionArmToken -TenantId <client>`, CLAUDE.md §3 / ADR-0018). Endpoints:

- `GET /subscriptions?api-version=2022-12-01`
- `GET /subscriptions/{sub}/resourcegroups?api-version=2022-09-01`
- `GET /subscriptions/{sub}/resources?api-version=2022-09-01`

All reads — never mutates any client's Azure. Paging follows `nextLink`
(`Invoke-ImperionArmRequest`). Per-tenant isolation: every row is stamped with the tenant
authenticated against; an unconsented tenant throws on token acquisition and the task's
per-tenant catch logs + skips it (fail closed — never silently mis-attributed).

## Tenant fan-out & cadence

**Daily** — cloud inventory drifts slowly; the change-detected upsert keeps re-runs cheap.
The task reads `IMPERION_M365_TENANT_IDS` (comma-separated client tenant ids, the same
fan-out idiom as the `m365/*` tasks) and calls the get → post once per tenant; an empty list
falls back to the partner tenant only (dormant-safe). Registration is deferred to server
bringup (#102), run-as the local service account (ADR-0012).

## Gates (dormant-safe)

- **Schema gate.** Until the front-end `cloud_*` migration is applied to prod, the post-layer
  upsert fails loudly (the table is absent — ADR-0005 fail-loud). The task's per-tenant
  `try/catch` logs a Warn and continues, so the schedule never crashes (identical to
  `azure/dns-zones` pre-`0080`). The next run converges once the table exists.
- **Identity / consent gate.** No consented client tenants configured ⇒ partner-tenant-only;
  no cert-SP context / SecretStore ⇒ token acquisition fails loudly and the same catch exits
  clean. No-op + log, never a crash.

## CONFIRM-BEFORE-LIVE

Before this runs LIVE against real client tenants (same precedent as DNS posture / security
incidents):

- Confirm per-tenant **subscription visibility** under the onboarding-app's Reader grant in a
  real client tenant (the onboarding app must have an ARM role assignment in that tenant /
  subscription — Reader — for `/subscriptions` to return rows; an empty list is a no-op, not
  an error).
- Confirm the **ARM api-versions** are current for the client estates and the resource fields
  the CMDB wants are in the flat column set (extras always survive in `raw_payload`).
- Confirm `IMPERION_M365_TENANT_IDS` is the right fan-out list for ARM (it is shared with the
  `m365/*` Graph tasks; if ARM consent differs from Graph consent, a dedicated env list is a
  follow-up).

## Downstream (later #201 slices)

Silver `cloud_asset` + the CMDB cloud-asset CI stitch (relate to account + device, front-end
ADR-0078) and the device-merge precedence note (below `website`, ADR-0039) are **later slices
of #201** — out of scope for slice 1. They carry a front-end OKF concept-file +
`coverage-matrix.md` update (system §11) when they land.

## Provenance

Rows stamped `source='azure_arm'` / `collected_at`; full payload in `raw_payload` (lossless);
`content_hash` drives change detection. No secrets logged (the ARM token rides the
`Authorization` header only).
