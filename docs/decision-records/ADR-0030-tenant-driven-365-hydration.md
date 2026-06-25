# ADR-0030: Tenant-driven 365 hydration — registry-resolved per-tenant credentials, no home special-case

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
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

1. **Registry-resolved credentials for every tenant, every data-read plane, cert OR secret, driven
   by the DB.** Remove the partner-tenant short-circuit; all tenants (Imperion included) resolve
   through `Resolve-ImperionTenantCredential`, which already branches on `auth_method`. There is **no
   PowerShell branch specific to the home tenant** for any data read — the home tenant is just the
   default `TenantId`, resolved from the registry like every client. The LP config SP is reserved for
   **infra/bootstrap tokens only** (Postgres, Key Vault, Storage) — **never** for any tenant data
   read (Graph *or* ARM).
2. **One app per tenant, both data planes — Microsoft Graph AND Azure ARM.** `Get-ImperionArmToken`
   resolves the **same** `m365` registry credential as `Get-ImperionGraphToken` (the provider
   argument changes `'azure'` → `'m365'`); there is **no separate `azure` provider row**. The
   per-tenant onboarding app is expected to hold **Global Reader on the tenant root management group**
   (the ARM read grant) **alongside** its read-only Graph application permissions — one read-only app
   covering 365 *and* Azure for that tenant. This removes the last reliance on the config SP's ARM
   Reader for data collection.
3. **Rename** the misnamed `Get-ImperionTenantAppToken` → `Get-ImperionRegisteredTenantToken`
   ("resolve the registered credential → connect"), keeping a thin alias for one release.
4. **Tenant-driven orchestration.** A new driver — `Invoke-ImperionTenantHydration` — enumerates
   active/consented tenants from the registry (`account_tenant` ⨝ `connection`), acquires each
   tenant's token **once**, runs **all** 365 + Azure routines for that tenant, then cycles to the next
   client. This reverses the per-collector fan-out: **tenant-outer, routines-inner**.
5. **GUI-save is the enable.** No push path is added; the driver reads the registry each run, so a
   credential entered in the GUI is picked up on the next run. Fail closed for any tenant without a
   current, consented credential (CLAUDE.md §3).

## Consequences

### Security impact

One read-only app (the per-client onboarding app) authenticates every tenant for **both** Microsoft
Graph **and** Azure ARM; the LP certificate SP is reduced to **infra/bootstrap tokens only** (PG / Key
Vault / Storage) and keeps **no Graph or ARM data reach** — so a stolen home-server cert can neither
read 365 nor enumerate Azure resources (least privilege, CLAUDE.md §2). The onboarding app's new ARM
grant is **Global Reader (read-only)** on the tenant root management group, consistent with the
read-only-by-default Azure posture (§2) — it is a *read* widening of one already-trusted read app, not
a new write surface. Per-tenant isolation is preserved (one tenant's failure → skip + warn, never
cross-tenant reads). Cert-vs-secret is the registry's call, never hard-coded.

### Cost impact

Lower Graph token churn — one token per tenant reused across that tenant's routines instead of
re-acquired per collector.

### Operational impact

A client's full 365 + Azure picture lands together, with per-tenant success/failure visibility.
Reverses the §5 "one task per (source,entity), collector fans out per tenant" framing for the 365
*and* ARM planes: the scheduled entry becomes the per-tenant driver.

**Data dependency (verified against prod registry 2026-06-24).** Imperion's account
(`b98b943b…`) currently has **two** `m365` rows — the grantless LP config SP (cert `46f1077b`, no
tenant, no Graph) **and** the Graph-consented onboarding app (secret `0d6c8db7`, tenant
`49307c12`, KV `conn-client-m365-49307c12…`). With both keyed to the same account the resolver is
**ambiguous** and can pick the dead cert row — a second cause of the 403s beyond the home
short-circuit. The GUI **credential-purge** capability (frontend #1282 / backend #390) must land
first to delete the dead config-SP row; the onboarding-app row **already exists**, so **no re-seed
is required** — purge alone disambiguates. The one new cloud grant this ADR assumes is **Global
Reader on the root management group** for the onboarding app (the ARM read, Decision #2).

## Future considerations

- Azure ARM `cloud-resources` is now **in scope** (Decision #2: same onboarding app, provider
  `m365`). The remaining per-tenant plane still to fold in is **DNS posture** — whether it adopts
  the tenant-driven driver or keeps independent fan-out.
- Sub-daily cadences per tenant (the `$tasks` schema is daily-only today; epic #286).

## Cross-references

ADR-0028 (per-tenant credential resolution — the resolver reused here), ADR-0029 (DB-authoritative
company credential resolution — same registry-as-authority principle), pipeline ADR-0018 (per-client
onboarding app), frontend ADR-0103 (the `connection` credential registry). Epic #324; frontend
#1282 / backend #390 (credential purge, the data-fix dependency).
