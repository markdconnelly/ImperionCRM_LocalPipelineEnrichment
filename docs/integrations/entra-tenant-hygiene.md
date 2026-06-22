# Integration — Entra tenant hygiene (domains · app registrations · role assignments)

**Purpose.** Close the tenant-hygiene gap left by the Azure inventory / service-principal
collectors: capture a tenant's **domains**, **application registrations**, and **directory
role assignments** so the front-end can benchmark them against standards (issue #219/#142;
front-end migration 0136 / benchmark issue ImperionCRM#260). Read-only Graph; flatten → bronze; no
IT Glue write (these are directory-config objects, not the operational/infrastructure data
the IT Glue hub documents — CLAUDE.md §6).

> **Not service principals.** `m365_service_principals` (the per-tenant *instance* of an
> app) is already collected by `Invoke-ImperionAzureInventorySync` /
> `Invoke-ImperionServicePrincipalSync`. App **registrations** are the app *definition* in
> its home tenant — the gap this closes, alongside domains and privileged-role membership.

## Auth
- **Cert-based app-only** token (`Get-MsalToken -ClientCertificate`) for Microsoft Graph,
  scope `https://graph.microsoft.com/.default`. Same cert SP as every other Graph collector.
- **Graph application permissions required (read-only):**
  - `Domain.Read.All` — `/domains`
  - `Application.Read.All` — `/applications`
  - `RoleManagement.Read.Directory` — `/roleManagement/directory/roleAssignments`
  - All three are part of the onboarding app's **read-only-by-default** grant (pipeline
    ADR-0018); none is a write or data-plane grant. Adding/consenting them is a
    human-approval gate (CLAUDE.md §8).
- **Tenant scope:** Imperion's own tenant by default. Client tenants fan out via the
  per-client onboarding app (`IMPERION_M365_TENANT_IDS`, CLAUDE.md §3); each row is
  stamped with its owning tenant (per-tenant isolation).

## Source endpoints (paged via `@odata.nextLink`)
| Object | Endpoint | Notes |
| --- | --- | --- |
| Domains | `GET /v1.0/domains` | `id` = the domain FQDN (the Graph key) |
| App registrations | `GET /v1.0/applications` | credential arrays (`keyCredentials`, `passwordCredentials`) drive the hygiene signal |
| Role assignments | `GET /v1.0/roleManagement/directory/roleAssignments?$expand=roleDefinition,principal` | `$expand` resolves the role name + principal in one page |

## Flattened fields (the hygiene signals)

The flat columns are **exactly the migration-0136 set** — the bronze filter. Everything the
source returns beyond these (verified publisher, identifier URIs, tags, the full credential
arrays, role template/built-in, principal UPN, app scope, domain admin-managed / password
policy, …) is over-collected losslessly into `raw_payload` (CLAUDE.md §5/§6); silver narrows
from there.

- **Domains** → `domain_name` · `is_verified` · `is_default` · `is_initial` ·
  `authentication_type` · `supported_services` (joined). *Benchmark reads:* unverified /
  federated / default-domain posture.
- **App registrations** → `app_id` · `display_name` · `sign_in_audience` · `publisher_domain` ·
  `created_date_time` · `key_credential_count` · `password_credential_count` ·
  `earliest_credential_expiry` (the single nearest expiry across **both** cert + secret
  credentials) · `has_expired_credential`. *Benchmark reads:* expiring/expired credentials,
  secret-bearing apps.
- **Role assignments** → `role_definition_id` · `role_display_name` · `is_privileged` (from the
  expanded roleDefinition) · `principal_id` · `principal_type`
  (`user`/`group`/`servicePrincipal`, trimmed from `@odata.type`) · `principal_display_name` ·
  `directory_scope_id` · `assignment_type` (`Assigned`; this endpoint returns active
  assignments — PIM-eligible `Activated` is a future enhancement). *Benchmark reads:* who holds
  privileged directory roles (e.g. Global Administrator); over-broad / unexpected grants.

Bronze flat columns are all-text (booleans → `'true'`/`'false'`, collections → delimited);
the full lossless objects live in `raw_payload` (CLAUDE.md §4/§6).

## Postgres targets (bronze — standard envelope)
`entra_domains` · `entra_app_registrations` · `entra_role_assignments` (logical source
`m365`) — flattened columns + `tenant_id`, `source`, `external_id`, `content_hash`,
`collected_at`, `raw_payload (jsonb)`. Upsert on `(tenant_id, source, external_id)`,
change-detected. `external_id` = domain FQDN / application object id / role-assignment id
respectively. **Schema is owned by the front end** (migration **0136** / ImperionCRM#260,
**applied to prod**; this repo never creates the tables). The tables are prod-applied but
**EMPTY** until a tenant is registered/consented; the writer still fails loudly if the
table/grant is ever missing (deploy-ahead safe).

## Cmdlets
- Get layer (collect → flatten, no write): `Get-ImperionEntraDomain` ·
  `Get-ImperionEntraAppRegistration` · `Get-ImperionEntraRoleAssignment`.
- Post layer (write flat rows → bronze, change-detected): `Set-ImperionEntraDomainToBronze`
  · `Set-ImperionEntraAppRegistrationToBronze` · `Set-ImperionEntraRoleAssignmentToBronze`.
- Scheduled fan-out (per-tenant): `Invoke-ImperionEntraDomainSync` ·
  `Invoke-ImperionEntraAppRegistrationSync` · `Invoke-ImperionEntraRoleAssignmentSync`.
- Registered scheduled tasks (daily; `Register-ImperionTask`, ADR-0007 — no loose entry
  scripts): `Imperion-EntraDomains` · `Imperion-EntraAppRegistrations` ·
  `Imperion-EntraRoleAssignments` (see the scheduled-task registry).

## Rate limits & retry
Graph throttles per-tenant; honor `Retry-After` on 429 with exponential backoff (handled by
`Invoke-ImperionRestWithRetry`). Page politely. Log record counts + duration per run.

## Assumptions to confirm on first live run
- The onboarding app has `Domain.Read.All`, `Application.Read.All`, and
  `RoleManagement.Read.Directory` admin-consented in Imperion's own tenant (and per client
  tenant for client fan-out).
- The front-end `entra_domains` / `entra_app_registrations` / `entra_role_assignments` bronze
  migration (**0136** / ImperionCRM#260) is applied to prod and the local-pipeline SP has the
  write grant on them (granted in 0136 itself).
- Live run is gated on the on-prem host coming online (#102) + a registered/consented tenant;
  deploy-ahead is safe (the sync self-gates and exits cleanly with no tenants).
- `roleDefinition.isPrivileged` is populated by `$expand=roleDefinition` (v1.0); where a tenant
  doesn't return it, `is_privileged` lands empty (benchmark treats absent as non-privileged).
