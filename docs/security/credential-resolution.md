# Credential resolution — how this node gets every secret it needs

How the on-prem pipeline resolves the credentials for **every** source and tenant, end to
end, without holding the secret material itself. This is the onboarding map for "where does
the IT Glue key / the m365 token / the Postgres login actually come from."

> **The one-sentence model.** The only secret this node stores locally is **its own app
> credential**; everything else is resolved at run time from the database `connection`
> registry → Azure Key Vault, exactly the way the backend and the cloud Pipeline resolve it
> — one credential per provider across all three planes, no divergent copies.

Governing decisions: **ADR-0028** (per-tenant/client-scope resolver), **ADR-0029**
(DB-authoritative company-scope resolver), **ADR-0030** (tenant-driven 365/Azure hydration).
The registry itself is front-end **ADR-0103**; the credential store is backend **ADR-0034**.
See also [`certificate-trust-chain.md`](certificate-trust-chain.md) and
[`least-privilege-grants.md`](least-privilege-grants.md).

---

## The resolution chain

```
SecretStore (this host)              ── holds ONLY the node app credential
  └─ node app credential ─────────▶  mint a short-lived Key Vault token (cert-backed app SP)
                                            │  (the SP holds Key Vault Secrets User)
DB `connection` registry  ◀────────────────┘  read the authoritative row for (provider, scope[, account])
  row: provider · scope · account_id · auth_method · keyvault_secret_ref · status
        │  follow keyvault_secret_ref
        ▼
Azure Key Vault  ──▶  JSON credential blob  ──▶  ConvertFrom-ImperionCredentialBlob (extract field)
        │
        ▼
the source/tenant credential (api key · client secret · cert thumbprint) — used, never stored
```

The database row is **authoritative**: the front-end GUI writes the secret to Key Vault and
records its name (`keyvault_secret_ref`) on the row. This node never invents a Key Vault name
and never keeps a second copy of the secret. **GUI-save is the enable** (ADR-0030): a
credential entered in the GUI is picked up on the next scheduled or on-demand run because the
resolver enumerates the registry each run — there is no push/trigger path (this node has no
inbound surface).

**Fail closed.** A provider/tenant with no current, active registry row + Key Vault secret
resolves to `$null` (or throws under `-FailClosed`); its collector logs and exits cleanly —
it is never run against dead access (`CLAUDE.md §3`).

---

## Three credential classes

| Class | Resolver | Authority | In prod today |
|---|---|---|---|
| **Client-scope (per-tenant 365 / Azure)** | `Resolve-ImperionTenantCredential` (ADR-0028) | `connection` row `scope='client'`, keyed by `account_id`; branches on `auth_method` | 2 `m365` rows, both `auth_method='secret'`, active |
| **Company-scope vendor (registry-backed)** | `Resolve-ImperionCompanyCredential` (ADR-0029) → `Resolve-ImperionVendorSecret` / vendor catalog | `connection` row `scope='company'` → KV blob | itglue · pax8 · myitprocess · televy · quotemanager · darkwebid · meta · qbo (apollo/docusign rows `status=error`, dormant) |
| **LP-only named secret (no registry row)** | the vendor catalog reads a **named** Key Vault secret directly | a fixed `conn-company-<provider>` KV name | cdw · easydmarc · datto rmm · datto bcdr · amazonbusiness |

The split exists because some sources are LP-only and have no front-end provider row to drive
them; those read a fixed KV name instead of a registry row. Both paths read **only** Key
Vault — the SecretStore-mirror tier and the old hard-coded `VaultDefault` names are gone
(ADR-0029).

### The credential blob

Company-scope secrets are custodied as a **JSON credential blob** in Key Vault under the
standardized `conn-company-<provider>` name (the GUI/backend write it; FE ADR-0103).
`ConvertFrom-ImperionCredentialBlob` parses the blob and extracts the needed field — e.g.
`apiKey` for a bearer source, `username`+`password` for Basic auth (Dark Web ID, #349),
`clientId`+`clientSecret` for an OAuth/client-credentials source. Reading a raw-string secret
or a wrong KV name is the drift this standardization closed (#291/#299).

---

## Tenant-driven 365 + Azure hydration (ADR-0030)

The Microsoft data planes — Graph (365/Entra/Intune/Defender/SharePoint) **and** Azure ARM —
resolve **every** tenant the same way, including the home/Imperion tenant. There is **no
PowerShell branch for the home tenant**: it is just the default `TenantId`, resolved from the
registry like any client (client-zero).

- **One read app per tenant, both planes.** `Get-ImperionGraphToken` and
  `Get-ImperionArmToken` resolve the **same** `m365` registry credential (the provider arg is
  `'m365'` for both — there is no separate `azure` provider row). The per-client onboarding
  app is expected to hold **Global Reader on the tenant root management group** (the ARM read)
  *alongside* its read-only Graph application permissions.
- **The node's cert SP never reads tenant data.** It is reserved for **infra/bootstrap tokens
  only** — Postgres, Key Vault, Storage. It holds no Graph or ARM data reach, so a stolen
  home-server cert can neither read 365 nor enumerate Azure resources (least privilege,
  `CLAUDE.md §2`). This corrects the old home-tenant short-circuit that authenticated Graph
  with the grantless cert SP and returned 403 across the estate.
- **Tenant-outer, routines-inner.** `Invoke-ImperionTenantHydration` enumerates
  active/consented tenants (`account_tenant ⨝ connection`), acquires each tenant's token
  **once**, runs **all** 365 + Azure routines for that tenant, then moves to the next — so a
  client's full picture lands together with per-tenant success/failure visibility. This
  reverses the older per-collector fan-out.
- **Rename:** `Get-ImperionTenantAppToken` → `Get-ImperionRegisteredTenantToken` (thin alias
  kept one release).

`Resolve-ImperionTenantCredential` already branches on `auth_method`:
`'certificate'` → `ClientId` + `CertThumbprint`; `'secret'` → `ClientId` + a `ClientSecret`
read from Key Vault by `keyvault_secret_ref`. Cert-vs-secret is the registry's call, never
hard-coded.

---

## End-state and what's still moving

**Target end-state (ADR-0029, epic #318):** the **only** secret this node reads from the
local SecretStore is its own app credential (`Get-ImperionNodeCredentialArg`), used to mint
the Key Vault token. Everything else is DB→KV.

- **Still on the SecretStore (own follow-up PRs):** autotask, qbo, voyage (the embedding key),
  mileiq, docusign. The `secret-names` cleanup + the `CLAUDE.md §2/§7` rewrite land with the
  last one. QBO's rotating OAuth refresh is owned by the **backend** (it custodies the refresh
  token and publishes a short-lived access token to KV, mirroring MileIQ — backend #385).
- **Registry data cleanup (GUI/Mark):** the `gdap` row is already purged in prod; `docusign`
  and `apollo` rows remain `status=error` (stale `kv://` ref) and stay dormant until re-seeded
  via the GUI.
- **Meta** reads a named KV secret pending token-type reconciliation (the FE page-send token
  differs from the LP system-user read token) before it becomes registry-backed.
- Legacy-name retirement for the remaining on-prem connections is **#292**.

---

## Why this shape

- **One credential, three planes.** The backend, the cloud Pipeline, and this node all follow
  the same `connection` row to the same Key Vault secret. Two resolution models for one
  credential is exactly how the planes silently drift onto different secrets.
- **Less to custody on the home server.** The SecretStore stops being a second secret store to
  provision, rotate, and protect; secret material lives only in Key Vault, read by the cert SP
  holding `Key Vault Secrets User`. No new write grant — this node stays read-only on Key Vault.
- **Change in one place.** A credential is rotated in the GUI (which writes KV + the row); this
  node picks it up on the next run with no host-side step.

## Cross-references

- ADRs: [ADR-0028](../decision-records/ADR-0028-provider-agnostic-per-tenant-credential-resolution.md) ·
  [ADR-0029](../decision-records/ADR-0029-db-authoritative-company-credential-resolution.md) ·
  [ADR-0030](../decision-records/ADR-0030-tenant-driven-365-hydration.md).
- [`certificate-trust-chain.md`](certificate-trust-chain.md) — the node app credential that
  mints the KV token. [`least-privilege-grants.md`](least-privilege-grants.md) — the cert SP's
  grant set.
- Sibling authorities: front-end **ADR-0103** (the `connection` credential registry),
  backend **ADR-0034** (credential storage).
- Current/volatile status: [`../STATE.md`](../STATE.md).
