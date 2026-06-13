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

## Provenance

Rows stamped `source='dns'` / `collected_at`; full ARM payload in `raw_payload` (lossless);
`content_hash` drives change detection. No secrets logged.
