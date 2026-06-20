# ADR-0028: Provider-agnostic per-tenant credential resolution from the connection registry

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-19 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0002 (certificate-rooted unattended execution — the master identity) · ADR-0023 (Azure ARM per-tenant cloud-resource inventory) · ADR-0026 (merge co-locates with ingestion) · frontend ADR-0103 (the `connection` credential registry: scope + account_id + cert-or-secret) · backend #217 (per-client app custody, cert-or-secret) · LP #234 (estate fan-out over `account_tenant`) · LP #250 (the m365 slice) |

> **ADR number is a placeholder** — claimed at merge (§10.3). Rename + fix references just before squash.

## Problem

The pipeline must poll **many** customer estates, not one: multiple **Microsoft tenants**
and multiple **UniFi consoles**, each reached with **that client's own** credential. Today
the fan-out exists (`Invoke-ImperionCloudResourceSync` iterates `account_tenant`, LP #234)
but every tenant's token is minted with the **home** app credential from
`pipeline.config.psd1` (`ClientId` + `CertThumbprint`). There is **no code that reads the
`connection` registry** to resolve a per-client credential, so:

- A client tenant can only be read if the *home* app happens to be consented there — which
  is not the per-client-app model the system chose (backend #217, frontend ADR-0103).
- UniFi has a single company-wide API key (`Get-ImperionUniFiDevice -ApiKey`, #73) with no
  per-console notion.
- Imperion's **own** M365 estate (`m365_groups` / `m365_*devices` = 0 in prod) is dark
  because the home SSO app `46f1077b` holds only `Mail.Send` as an application Graph role —
  it cannot read directory/device/security.

The credential *registry* and its GUI are already built (frontend ADR-0103, migration 0141;
catalog #905 + account panel #906): `connection(scope, provider, account_id,
external_account_id, keyvault_secret_ref, auth_method, cert_thumbprint, client_id,
poll_interval_minutes)` and `account_tenant(tenant_id → account_id)`. What is missing is the
**runtime consumer** on this node.

## Context

- **The token plumbing is already per-tenant and cert-or-secret.** `Get-ImperionAccessToken`
  (and the `Get-ImperionGraphToken` / `Get-ImperionArmToken` wrappers) accept `-TenantId` +
  a credential splat (`@{ ClientId; CertThumbprint }` or `@{ ClientId; ClientSecret }`) and
  cache per `(tenant, resource)`. They currently default the credential to the home app.
- **Key Vault read exists.** `Get-ImperionKeyVaultSecret` reads a secret by name using the
  master cert SP (which holds `Key Vault Secrets User`). The established resolver shape is
  `Resolve-ImperionVendorSecret` (three-tier, company-wide).
- **The master identity reads Key Vault; the client credential does the polling.** This is
  the security model Mark restated (2026-06-19): functions authenticate to Key Vault **as
  the Imperion CRM identity**, fetch the **appropriate client's** credential, and use it to
  reach that client's tenant/console.
- **Per-client apps, not a widened home app.** Granting broad directory/device/security
  *application* roles onto the user-facing SSO app would fork least privilege (CLAUDE.md
  §2/§3). Each client tenant consents its own per-client app; the home tenant is no
  exception.

## Options considered

1. **Widen the home app (`46f1077b`) with read roles + reuse it for every tenant.** Fastest
   to fill the home estate, but it is single-app multi-tenant (needs the home app consented
   in every client tenant), over-grants a user-facing app, and contradicts backend #217.
   Rejected.
2. **A per-provider resolver each (m365-only #250, separate UniFi path).** Ships the m365
   slice sooner but duplicates the registry-read + KV + fail-closed logic three times and
   leaves UniFi a special case. Rejected — Mark chose one shared resolver.
3. **One provider-agnostic resolver reading the `connection` registry (chosen).** A thin,
   high-reuse adapter — like `Resolve-ImperionVendorSecret` — that every collector calls to
   turn `(account, tenant, provider)` into a credential splat.

## Decision

Add a single provider-agnostic resolver and route all per-tenant/per-console collectors
through it.

### The resolver
`Resolve-ImperionTenantCredential -AccountId <guid> -TenantId <guid> -Provider <name>
[-FailClosed]` (Private; mirrors `Resolve-ImperionVendorSecret`):

1. **Read the registry.** `SELECT … FROM connection WHERE account_id = @AccountId AND
   provider = @Provider AND scope = 'client'` (most-recent active row). No row → `$null`,
   or **throw if `-FailClosed`**. A tenant/console with no consented credential is **never
   touched** (fail-closed — CLAUDE.md §3).
2. **Branch on `auth_method`** to a credential splat the existing primitives already accept:
   - `cert`   → `@{ ClientId = client_id; CertThumbprint = cert_thumbprint }`
   - `secret` → `@{ ClientId = client_id; ClientSecret = (Get-ImperionKeyVaultSecret keyvault_secret_ref) }`
   - `api_key`→ `@{ ApiKey = (Get-ImperionKeyVaultSecret keyvault_secret_ref) }`
3. **Never materialize a secret outside the splat.** No secret value is logged, returned in
   error text, or written to disk. The master cert SP is the only identity that reads Key
   Vault.

### Provider adapters (no new token code)
- **graph (m365):** resolution is centralized in the `Get-ImperionGraphToken` **seam** every
  m365 collector already funnels through (the m365 slice, #250) — rather than repeating a
  resolve-then-splat in each of ~20 collectors (the shallow-adapter pattern the architecture
  review warns against). For a managed client tenant (`TenantId ≠ PartnerTenantId`) the seam
  looks up the owning account (`account_tenant`), calls the resolver `-FailClosed`, and mints
  with the client's own app id + cert/secret; the partner/home tenant keeps the home
  enterprise-app credential (DB-free path, no recursion through `New-ImperionDbConnection`).
  Every collector becomes per-tenant-credential-aware with **zero collector edits**.
- **azure (ARM):** pass the splat to `Get-ImperionArmToken -TenantId $TenantId` from the
  cloud-resource sweep (#258). Per-tenant token caching already isolates by tenant.
- **unifi:** `external_account_id` selects the console/site; the `@{ ApiKey }` feeds
  `Invoke-ImperionUniFiRequest`. Multiple consoles per account are multiple registry rows.

### Wiring
Collectors keep their existing `account_tenant` (m365/ARM) / console (UniFi) fan-out; each
iteration first resolves its credential, **fail-closed per item** (skip + `Warn`, never
block the estate — the LP #234 precedent). Per-tenant isolation is absolute: every bronze
row is stamped with its owning tenant/account; no cross-tenant read in any query path.

### Home tenant = client-zero
Imperion's own tenant is onboarded as a **normal registry row** (its own read app +
admin consent), resolved by the same path as any client. No special-casing, no broad grant
on the SSO app. (Front-end seeding + per-client credential-entry UX: markdconnelly/ImperionCRM
#950.)

### Cadence
`poll_interval_minutes` on the `connection` row is the per-source cadence authority; the
scheduled task is the outer loop, the resolver/collector honors the interval.

## Consequences

### Security impact

Strengthens least privilege. The master cert SP keeps only `Key Vault Secrets User` +
`Reader`; **no directory/device/security application roles are added to the home app.** Each
client's read grants live on that client's per-client app, consented in that client's
tenant, severable by deleting one registry row / KV secret (fail-closed, ADR-0002/§3). No
secret is logged or persisted; resolution is KV-only. Per-tenant isolation holds — bronze
rows carry their owning tenant, and the resolver keys on `account_id` so one account can
never resolve another's credential. Adding a registry row is the per-client onboarding
security event (CLAUDE.md §3/§8) — surfaced, human-approved, not added for convenience.

### Cost impact

Negligible. One extra indexed `connection` read per (tenant, provider) per run, plus a Key
Vault GET per non-cert credential (cacheable for the run). No new external API classes.

### Operational impact

- New Private cmdlet `Resolve-ImperionTenantCredential` (#257); the m365 (#250 — via the
  `Get-ImperionGraphToken` seam), ARM (#258), and UniFi (#259) collectors are re-pointed at it.
- **Fail-closed for m365 = throw** at `Get-ImperionGraphToken` (an unmapped or unconsented
  client tenant mints no token). The ARM sweep (`Invoke-ImperionCloudResourceSync`, LP #234)
  already wraps each tenant in try/catch, so a throw becomes skip + `Warn` there. The m365
  `.task.ps1` fan-out does **not** yet isolate per tenant — adding that try/catch so one
  unconsented tenant never aborts the m365 estate run is a follow-up.
- Until client rows are seeded, the resolver returns `$null` for every client and the estate
  stays home-only — this is **safe and visible** (a Warn per unconsented tenant), not a
  crash. Hydration of client estates is gated on onboarding data (the registry), exactly as
  intended.
- The home estate lights up the moment the client-zero row is seeded (#950) — independent of
  any Graph grant on the SSO app.

## Future considerations

- A resolved-credential cache (per run, by `connection.id`) if KV GET latency matters at
  fan-out scale.
- `sync_cursor` / `last_sync_at` on the `connection` row enable per-tenant incremental
  windows — a natural follow-up once multi-tenant pulls are live.
- The same resolver generalizes to any future per-client source (Datto, etc.) by adding a
  `provider` + adapter, never new credential plumbing.

## Cross-references

ADR-0002 (master cert identity) · ADR-0023 (ARM per-tenant inventory) · ADR-0026 (merge
co-locates) · frontend ADR-0103 (the `connection` registry) · backend #217 (cert-or-secret
custody) · LP #234 (estate fan-out) · LP #250 (m365 slice) · LP #255 (epic) · LP #257
(resolver core) · LP #258 (ARM wiring) · LP #259 (UniFi) · frontend #950 (client-zero seed +
credential-entry UX).
