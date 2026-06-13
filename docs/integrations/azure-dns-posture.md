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
with a **DNS-over-HTTPS** fallback to `dns.google`), so there is no GDAP/per-client
dependency. Per domain it resolves apex A / TXT (SPF) / MX / NS / CAA, DMARC (`_dmarc` TXT),
and the common M365 DKIM selector CNAMEs (`selector1/2._domainkey`).

**Domain source = `account_domain`** (the GUI-managed per-account list, migration 0081 /
ADR-0063 amendment #334). The task reads it (`Invoke-ImperionDbQuery`) and resolves per
`(account, domain)`. Domains are **account-scoped**: the owning account is the row isolation
key, so `tenant_id` carries the account id for public rows and `account_id` is stamped
explicitly for the silver merge (#157). `external_id = '<domain>|public|<type>|<name>'` —
never collides with the azure plane. Gated on migration 0081; an empty list is a no-op.

## Provenance

Rows stamped `source='dns'` / `collected_at`; full payload in `raw_payload` (lossless);
`content_hash` drives change detection. No secrets logged.
