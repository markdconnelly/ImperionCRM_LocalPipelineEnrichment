# Integration — Entra service principals → IT Glue

**Purpose.** Inventory every Entra ID **service principal** (enterprise apps + app
registrations' SPs) in a tenant, flatten the attributes that matter, and document them as
IT Glue flexible assets related to the owning organization. The same flat table also lands
in Postgres bronze.

## Auth
- **Cert-based app-only** token (`Get-MsalToken -ClientCertificate`) for Microsoft Graph,
  scope `https://graph.microsoft.com/.default`.
- **Graph permission required:** `Application.Read.All` *or* `Directory.Read.All`
  (application permission, read-only). This is part of the onboarding app's
  read-only-by-default grant (pipeline ADR-0018).
- **Tenant scope:** Imperion's own tenant by default. To inventory **client** tenants,
  acquire a client-credentials Graph token as the consented onboarding app **in each
  client tenant** (CLAUDE.md §3) and loop — one IT Glue organization per client tenant.
  *(The per-client-app multi-tenant loop is the documented extension; the first cut
  targets Imperion's own tenant.)*

## Source endpoint
`GET https://graph.microsoft.com/v1.0/servicePrincipals` (paged via `@odata.nextLink`).
Optionally enrich with `/servicePrincipals/{id}/appRoleAssignedTo`,
`/oauth2PermissionGrants`, and owners for a fuller picture.

## Flattened fields (the attributes we care about)
`id` · `appId` · `displayName` · `servicePrincipalType` · `accountEnabled` ·
`appOwnerOrganizationId` · `signInAudience` · `homepage` · `replyUrls` (joined) ·
`servicePrincipalNames` (joined) · `tags` (joined) · `appRoles` count ·
`oauth2PermissionScopes` count · `keyCredentials` count + **nearest expiry** ·
`passwordCredentials` count + **nearest expiry** · `createdDateTime` · `tenantId`.

> Credential expiry is the high-value signal — surface SPs with expiring/expired
> certificates or secrets.

## IT Glue modeling
- **Flexible Asset Type:** `Azure Service Principal` (created idempotently on first run).
- **Traits:** the flattened fields above; a **Tag trait** relating the asset to its IT Glue
  **Organization** (the tenant's org).
- **Change detection:** hash the flattened record (CLAUDE.md §6 /
  [change-detection](../operations/change-detection.md)); if unchanged since last run,
  **skip** the IT Glue write and the Postgres upsert.

## Postgres target (bronze)
`m365_service_principals` (logical source `m365`) — flattened columns + `tenant_id`,
`source`, `external_id` (= `id`), `content_hash`, `collected_at`, `raw_payload (jsonb)`.
Upsert on `(tenant_id, source, external_id)`.

## Rate limits & retry
Graph throttles per-tenant; honor `Retry-After` on 429 with exponential backoff. Page
politely. Log record counts + duration.

## Assumptions to confirm on first live run
- The onboarding app has `Application.Read.All`/`Directory.Read.All` admin-consented in
  Imperion's own tenant (and per client tenant for client inventory).
- IT Glue organization mapping: how a tenant id maps to an IT Glue organization (by name,
  by an org trait, or a maintained map).
