# Integration — Entra tenant hygiene (domains · app registrations · role assignments)

**Purpose.** Close the tenant-hygiene gap left by the Azure inventory / service-principal
collectors: capture a tenant's **domains**, **application registrations**, and **directory
role assignments** so the front-end can benchmark them against standards (issue #142;
front-end schema + benchmark issue ImperionCRM#260). Read-only Graph; flatten → bronze; no
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
  - All three are part of the **read-only-by-default** grant (ADR-0002); none is a write
    or data-plane grant. Adding/consenting them is a human-approval gate (CLAUDE.md §8).
- **Tenant scope:** the **partner tenant** by default. Customer tenants fan out over GDAP
  via `IMPERION_M365_TENANT_IDS` (CLAUDE.md §3); each row is stamped with its owning
  tenant (per-tenant isolation).

## Source endpoints (paged via `@odata.nextLink`)
| Object | Endpoint | Notes |
| --- | --- | --- |
| Domains | `GET /v1.0/domains` | `id` = the domain FQDN (the Graph key) |
| App registrations | `GET /v1.0/applications` | credential arrays (`keyCredentials`, `passwordCredentials`) drive the hygiene signal |
| Role assignments | `GET /v1.0/roleManagement/directory/roleAssignments?$expand=roleDefinition,principal` | `$expand` resolves the role name + principal in one page |

## Flattened fields (the hygiene signals)
- **Domains** → `domain_name` · `authentication_type` · `is_default` · `is_initial` ·
  `is_root` · `is_verified` · `is_admin_managed` · `supported_services` (joined) ·
  `password_validity_period_in_days` · `password_notification_window_in_days`. *Benchmark
  reads:* unverified / federated / default-domain posture.
- **App registrations** → `app_id` · `display_name` · `sign_in_audience` ·
  `publisher_domain` · `verified_publisher` · `identifier_uris` (joined) · `tags` (joined) ·
  `required_resource_access_count` · `key_credentials_count` + **nearest expiry** ·
  `pwd_credentials_count` + **nearest expiry** · `created_date_time`. *Benchmark reads:*
  expiring/expired credentials, secret-bearing apps, unverified publishers, multi-tenant
  audience.
- **Role assignments** → `role_definition_id` · `role_display_name` · `role_is_builtin` ·
  `role_template_id` · `principal_id` · `principal_display_name` · `principal_type`
  (`user`/`group`/`servicePrincipal`, trimmed from `@odata.type`) · `principal_upn` ·
  `directory_scope_id` · `app_scope_id`. *Benchmark reads:* who holds Global Administrator
  and other privileged roles; over-broad / unexpected grants.

Bronze flat columns are all-text (booleans → `'true'`/`'false'`, collections → delimited);
the full lossless objects live in `raw_payload` (CLAUDE.md §4/§6).

## Postgres targets (bronze — standard envelope)
`entra_domains` · `entra_app_registrations` · `entra_role_assignments` (logical source
`m365`) — flattened columns + `tenant_id`, `source`, `external_id`, `content_hash`,
`collected_at`, `raw_payload (jsonb)`. Upsert on `(tenant_id, source, external_id)`,
change-detected. `external_id` = domain FQDN / application object id / role-assignment id
respectively. **Schema is owned by the front end** (ImperionCRM#260) — this repo never
creates the tables; the post fails loudly until the migration is applied to prod
(deploy-ahead safe).

## Cmdlets
- Get layer (collect → flatten, no write): `Get-ImperionEntraDomain` ·
  `Get-ImperionEntraAppRegistration` · `Get-ImperionEntraRoleAssignment`.
- Post layer (write flat rows → bronze, change-detected): `Set-ImperionEntraDomainToBronze`
  · `Set-ImperionEntraAppRegistrationToBronze` · `Set-ImperionEntraRoleAssignmentToBronze`.
- Scheduled-task files: `scheduled-tasks/m365/entra-domains.task.ps1` ·
  `entra-app-registrations.task.ps1` · `entra-role-assignments.task.ps1` (daily; see the
  scheduled-task registry).

## Rate limits & retry
Graph throttles per-tenant; honor `Retry-After` on 429 with exponential backoff (handled by
`Invoke-ImperionRestWithRetry`). Page politely. Log record counts + duration per run.

## Assumptions to confirm on first live run
- The cert app has `Domain.Read.All`, `Application.Read.All`, and
  `RoleManagement.Read.Directory` consented in the partner tenant (and via GDAP roles for
  customer tenants).
- The front-end `entra_domains` / `entra_app_registrations` / `entra_role_assignments`
  bronze migration (ImperionCRM#260) is applied to prod and the local-pipeline SP has the
  write grant on them (follow-up grant migration, same as the 0036/0079 tables — see the
  registry's grant prerequisite note).
- Live run is gated on the on-prem host coming online (#102); deploy-ahead is safe (the
  post self-gates and exits cleanly until the schema lands).
