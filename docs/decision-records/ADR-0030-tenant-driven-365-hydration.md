# ADR-0030: Tenant-driven 365 hydration — registry-resolved per-tenant credentials, no home special-case

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-24 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0028, ADR-0029, pipeline ADR-0018, frontend ADR-0103 |
| **Amends** | the §5 "collector fans out per tenant" framing |

## Problem

The 365 (Microsoft Graph / Entra / Intune / Defender / SharePoint) collectors do not hydrate
every tenant the same way, and the home tenant doesn't hydrate at all:

- **The partner/home tenant is special-cased to the wrong app.** `Get-ImperionTenantAppToken`
  short-circuits: when the target tenant **is** the partner tenant it authenticates with the LP
  **config app** (`$cfg.ClientId` = the certificate service principal), not the credential
  registry. That SP holds Azure **Reader + Key Vault Secrets User + Postgres** but **no Microsoft
  Graph application permissions**, so every partner-tenant Graph call returns **403** (observed on
  the 2026-06-23 host run — users / groups / devices / domains / intune / defender / sharepoint
  all `Authorization_RequestDenied`).
- **The function name is a misnomer.** `Get-ImperionTenantAppToken` reads as "get a token" but is
  really the credential-resolution + connect seam for a tenant.
- **The nesting is backwards.** Each collector independently fans out over tenants, so a tenant's
  token is re-acquired per collector and a client's picture lands piecemeal across many jobs.

## Context

- The **credential registry is already the authoritative link** (ADR-0029, ADR-0103) and
  `Resolve-ImperionTenantCredential` (ADR-0028) **already supports both auth methods**, driven by
  the DB: `connection.auth_method = 'certificate'` → `ClientId` + `CertThumbprint`; `'secret'` →
  `ClientId` + `ClientSecret` read from Key Vault by the name on `keyvault_secret_ref`. The client
  path already uses it; only the home path bypasses it.
- LP has **no inbound network surface** (CLAUDE.md §1) — it is pull/registry-driven. So a
  credential saved in the GUI (which writes the `connection` row + KV secret) becomes available to
  LP automatically: the next scheduled (or on-demand) run **discovers** it by enumerating the
  registry. Entering the credential *is* the enable — no push/trigger.
- Client M365 access is the per-client onboarding app (pipeline ADR-0018, CLAUDE.md §3).

## Options considered

1. **Grant Microsoft Graph permissions to the LP config SP (46f1077b).** Quickest unblock, but
   widens the crown-jewel cert SP to Graph read across the estate — a stolen home-server cert then
   reads all of 365. Rejected as the standing model; violates least privilege (CLAUDE.md §2).
2. **Tenant-driven hydration via the registry (chosen).** Treat the home tenant as just another
   tenant (client-zero, ADR-0028): resolve its onboarding-app credential from the registry like
   every client. The LP config SP stays Azure/KV/PG-only. One read app (the onboarding app) for
   every tenant; cert-or-secret per the DB.

## Decision

1. **Registry-resolved credentials for every tenant, cert OR secret, driven by the DB.** Remove the
   partner-tenant short-circuit; all tenants (Imperion included) resolve through
   `Resolve-ImperionTenantCredential`, which already branches on `auth_method`. The config app is
   reserved for **infra tokens only** (Postgres, Key Vault, Storage; and ARM where a tenant has no
   registry row) — never for Graph.
2. **Rename** the misnamed `Get-ImperionTenantAppToken` → `Get-ImperionRegisteredTenantToken`
   ("resolve the registered credential → connect"), keeping a thin alias for one release.
3. **Tenant-driven orchestration.** A new driver — `Invoke-ImperionTenantHydration` — enumerates
   active/consented tenants from the registry (`account_tenant` ⨝ `connection`), acquires each
   tenant's token **once**, runs **all** 365 routines for that tenant, then cycles to the next
   client. This reverses the per-collector fan-out: **tenant-outer, routines-inner**.
4. **GUI-save is the enable.** No push path is added; the driver reads the registry each run, so a
   credential entered in the GUI is picked up on the next run. Fail closed for any tenant without a
   current, consented credential (CLAUDE.md §3).

## Consequences

### Security impact

One read-only Graph app (the per-client onboarding app) authenticates every tenant; the LP
certificate SP keeps **no Graph reach** — a stolen home-server cert cannot read 365 (least
privilege, CLAUDE.md §2). Per-tenant isolation is preserved (one tenant's failure → skip + warn,
never cross-tenant reads). Cert-vs-secret is the registry's call, never hard-coded.

### Cost impact

Lower Graph token churn — one token per tenant reused across that tenant's routines instead of
re-acquired per collector.

### Operational impact

A client's full 365 picture lands together, with per-tenant success/failure visibility. Reverses
the §5 "one task per (source,entity), collector fans out per tenant" framing for the 365 plane:
the scheduled entry becomes the per-tenant driver. **Data dependency:** the home (Imperion)
`m365` row currently points at the grantless LP config SP; it must be re-seeded to the
Graph-consented onboarding app — which needs the GUI **credential-purge** capability first
(frontend #1282 / backend #390) so the wrong certificate credential can be cleared.

## Future considerations

- Whether non-365 per-tenant planes (Azure ARM `cloud-resources`, DNS) adopt the same
  tenant-driven driver, or keep independent fan-out (they already work via the config SP's ARM
  Reader).
- Sub-daily cadences per tenant (the `$tasks` schema is daily-only today; epic #286).

## Cross-references

ADR-0028 (per-tenant credential resolution — the resolver reused here), ADR-0029 (DB-authoritative
company credential resolution — same registry-as-authority principle), pipeline ADR-0018 (per-client
onboarding app), frontend ADR-0103 (the `connection` credential registry). Epic #324; frontend
#1282 / backend #390 (credential purge, the data-fix dependency).
