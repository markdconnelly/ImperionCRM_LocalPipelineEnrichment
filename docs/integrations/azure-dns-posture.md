# Azure DNS posture — manage plane (ARM zones + recordsets)

**Issue:** local #155 · **Schema:** front-end migration `0080_dns_posture_bronze` ·
**Decision:** front-end ADR-0063 (DNS posture tracking) · **Source key:** `dns`

## Purpose

The Azure **manage plane** of per-customer DNS posture. Enumerates Azure DNS zones and
their recordsets, and proves whether Imperion can actually *manage* each zone — the
"hosted in Azure and manageable" process check. The public **ground-truth plane**
(resolver) is the sibling collector (local #156, `azure/dns-resolve`); the per-domain
golden baseline + drift rollup is the silver merge (local #157).

## Pipeline

| | |
|---|---|
| **Get** | `Get-ImperionDnsZoneObject -SubscriptionId <sub> [-TenantId]` |
| **Post** | `Set-ImperionDnsZoneToBronze` (multi-table router by `entity`) |
| **Tables** | `dns_zones` (entity `zones`), `dns_records` (entity `records`, `plane='azure'`) |
| **Task** | `scheduled-tasks/azure/dns-zones.task.ps1` — **Daily** |

Each zone yields one `dns_zones` row (`domain`, `in_azure`, `manageable`, `resource_group`,
`subscription_id`, `ns_records`, `verdict`) plus one `dns_records` row per recordset
(`record_type`, `name`, `value`, `ttl`). Standard bronze envelope, PK
`(tenant_id, source, external_id)`; record `external_id` is the composite
`<domain>|azure|<type>|<name>`.

## Auth & permissions

Cert-SP ARM token (`https://management.azure.com/.default`), **Reader** — already held,
**no new grant**. Endpoints:

- `GET /subscriptions/{sub}/providers/Microsoft.Network/dnsZones?api-version=2018-05-01`
- `GET {zoneId}/recordsets?api-version=2018-05-01`
- `GET {zoneId}/providers/Microsoft.Authorization/permissions?api-version=2022-04-01` —
  the **write-access probe** (`Test-ImperionArmWriteAccess`): reads the SP's *own effective
  permissions* at the zone scope and returns `manageable=true` only when a granted action
  covers `Microsoft.Network/dnsZones/recordSets/write` and no `notAction` removes it. This
  is a **read** — it never mutates the zone, and needs no principal-object-id lookup.

## Verdict

The collector sets a manage-plane verdict only: `managed` (write proven) or
`in-azure-readonly`. The final `not-in-azure | in-azure-readonly | managed` verdict — which
also requires the domain's live NS to delegate to the Azure zone — is computed by the
silver drift merge (#157), which has both planes. `not-in-azure` never originates here (a
`dns_zones` row exists only for zones that ARE in Azure).

## Cadence & gates

**Daily** — DNS drift is slow; the change-detected upsert keeps re-runs cheap. **Gated on
migration 0080 prod apply**: until applied the post fails loudly and the task's catch logs a
Warn and exits cleanly. Registration is deferred to server bringup (#102). Per-tenant
isolation: every row carries the tenant authenticated against.

## Public ground-truth plane (azure/dns-resolve, #156)

The sibling collector that captures **what the world sees** — the only signal for domains
not hosted in Azure DNS.

| | |
|---|---|
| **Get** | `Get-ImperionDnsResolveObject -Domain <d> -AccountId <id>` |
| **Post** | `Set-ImperionDnsRecordToBronze` (single-table -> `dns_records`, `plane='public'`) |
| **Task** | `scheduled-tasks/azure/dns-resolve.task.ps1` — **Daily** |

No Microsoft auth — pure public resolution via `Resolve-ImperionDnsRecord` (OS resolver
with a **DNS-over-HTTPS** fallback to `dns.google`), so there is no per-client
onboarding-app / tenant-access dependency. Per domain it resolves apex A / TXT (SPF) / MX / NS / CAA, DMARC (`_dmarc` TXT),
and the common M365 DKIM selector CNAMEs (`selector1/2._domainkey`).

**Domain source = `account_domain`** (the GUI-managed per-account list, migration 0081 /
ADR-0063 amendment #334). The task reads it (`Invoke-ImperionDbQuery`) and resolves per
`(account, domain)`. Domains are **account-scoped**: the owning account is the row isolation
key, so `tenant_id` carries the account id for public rows and `account_id` is stamped
explicitly for the silver merge (#157). `external_id = '<domain>|public|<type>|<name>'` —
never collides with the azure plane. Gated on migration 0081; an empty list is a no-op.

## Silver merge — golden state + drift rollup (local #157)

The silver half. Three cmdlets close the loop against migration-0080 `dns_golden` /
`dns_domain` (keyed `(tenant_id, domain)`, `account_id` carried for the account-scoped
read):

| | |
|---|---|
| **Approve baseline** | `Set-ImperionDnsGoldenState -Domain <d> -ApprovedBy <who>` (or `-All`) — **human-gated** |
| **Classify** | `Get-ImperionDnsDrift [-Domain <d>]` — read-only, returns per-domain verdict + counts + score |
| **Persist** | `Invoke-ImperionDnsMerge [-Domain <d>]` — upserts `dns_domain` (idempotent) |
| **Task** | `scheduled-tasks/azure/dns-merge.task.ps1` — **Daily, after both collectors** |

**Golden State (`Set-ImperionDnsGoldenState`).** Freezes a domain's current capture as its
approved baseline → `dns_golden.golden_records` (the jsonb record set, each with its
`content_hash`) + `golden_hash` (one stable hash over the whole-domain shape). Default plane
`public` (ground-truth, the only plane every domain has); `azure` available. **Approving a
baseline is a posture decision — gated** (`ShouldProcess`; runbook
`docs/operations/dns-golden-approval.md`). Idempotent (`ON CONFLICT` re-approves). Until a
domain is approved, every record classifies `ungoverned` — by design.

**Drift classification (`Get-ImperionDnsDrift`).** Per governed domain (from `account_domain`):

- **Record drift** — full-outer-joins the captured public-plane records vs `golden_records`
  on `(record_type, name)` and classifies each with the **same four-state CASE** as
  `Get-ImperionPolicyDrift` (ADR-0008 / ADR-0051 §3): `compliant` (hash match) / `drift`
  (changed) / `ungoverned` (no baseline) / `missing` (baseline gone). Counts roll up.
- **Governance verdict** — the three-state ladder (ADR-0063), **reconciled across both
  planes**: `not-in-azure` (no `dns_zones` row) → `in-azure-readonly` (zone exists but not
  write-proven, or NS not delegated) → `managed` (**in Azure AND write-proven AND the live
  public NS delegate to the Azure zone's nameservers**). The NS-delegation check is the
  cross-plane reconciliation (public NS records ∩ zone `ns_records`) — only then is the
  domain authoritative-in-Azure.
- **Score** — 0–100, the compliant share of governed records, capped at 60 unless `managed`.

The classification SQL is **owned by `Get-ImperionDnsDrift` and reused verbatim by the cloud
on-demand refresh** (parity contract, ADR-0063): change it in one place.

**Merge (`Invoke-ImperionDnsMerge`).** Calls the drift read, then upserts one `dns_domain` row
per domain (`tenant_id := account_id`, the isolation owner — falls back to the domain when
unmapped). Each domain upserts independently so one bad domain never blocks the fleet; the
whole run is idempotent and converges on re-run. **Gated** on migrations 0080 + 0081 prod
apply — the task's catch logs a Warn and exits cleanly.

## Provenance

Rows stamped `source='dns'` / `collected_at`; full payload in `raw_payload` (lossless);
`content_hash` drives change detection. No secrets logged.
