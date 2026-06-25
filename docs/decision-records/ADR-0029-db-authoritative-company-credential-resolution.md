# ADR-0029: DB-authoritative company credential resolution; SecretStore holds only the app credential

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-23 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0028, frontend ADR-0103, backend ADR-0034 |
| **Supersedes** | the company-vendor half of ADR-0009 (#228 three-tier vendor secret resolution) |

## Problem

LP resolved **company/MSP-wide** vendor credentials from hard-coded Key Vault names plus a
local SecretStore mirror (`Get-ImperionVendorSecretCatalog` / `Resolve-ImperionVendorSecret`),
and several collectors read the SecretStore directly. The backend and the cloud Pipeline,
meanwhile, read each credential from Key Vault by following the database `connection` registry
row (the GUI writes the secret to KV and records its name on the row). Two resolution models
for one credential is exactly how the three planes silently drift onto different secrets — and
it kept secret material in a second store (the SecretStore) that has to be provisioned and
rotated separately on the home server.

## Context

The **client**-scope path already does the right thing: `Resolve-ImperionTenantCredential`
(ADR-0028) reads the `connection` row → `keyvault_secret_ref` → Key Vault. Every company-scope
row in prod already carries the standardized `conn-company-<provider>` ref and the same JSON
credential blob the backend writes. So the authoritative link already exists in the database;
LP simply was not following it for company scope. No schema change is required.

## Options considered

1. **Keep hard-coded KV names + SecretStore mirrors** — status quo; drift and double custody persist.
2. **DB-authoritative company resolver (chosen)** — LP follows the `connection` registry row to
   Key Vault for company credentials, exactly as the client-scope path and the siblings do; the
   SecretStore keeps only the app credential that mints the KV token.

## Decision

Add `Resolve-ImperionCompanyCredential -Provider -Field [-Connection] [-FailClosed]` — the
company-scope mirror of `Resolve-ImperionTenantCredential`: select the newest active
`scope='company'` row for the provider, follow `keyvault_secret_ref` to Key Vault (read via the
cert-backed app SP), and extract the requested field from the JSON credential blob
(`ConvertFrom-ImperionCredentialBlob`). `Resolve-ImperionVendorSecret` / the vendor catalog cut
over to it: registry-backed providers (itglue, televy, quotemanager, myitprocess, pax8) resolve
DB→KV; LP-only vendors with **no** registry row (cdw, easydmarc, datto rmm/bcdr, amazonbusiness;
and meta, whose LP read token differs from the FE send token) read a **named Key Vault secret**
directly. The SecretStore-mirror tier and the hard-coded `VaultDefault` names are removed.

**Target end-state (rolled out across epic #318):** the **only** secret LP reads from the local
SecretStore is this node's own app credential (`Get-ImperionNodeCredentialArg`) used to mint the
Key Vault token. Autotask, QBO, Voyage, MileIQ, and DocuSign move off the SecretStore in their own PRs;
QBO's rotating OAuth refresh is owned by the backend (it custodies the refresh token and
publishes a short-lived access token to KV, mirroring MileIQ — backend #385).

## Consequences

### Security impact

One credential per provider across all three planes — no divergent copies. Secret material lives
only in Key Vault (read by the cert SP holding `Key Vault Secrets User`); the home-server
SecretStore stops being a second secret store to provision/rotate/leak. No new write grant: LP
stays read-only on Key Vault. Provider not connected → resolver returns `$null` (or throws with
`-FailClosed`) → collectors fail **closed**.

### Cost impact

Negligible: one extra short-lived DB query per credential resolution per run (reusable via the
optional `-Connection`).

### Operational impact

A credential is changed in one place — the GUI (which writes KV + the registry row); LP picks it
up with no host-side SecretStore step. Resolution now needs DB connectivity (already required to
write bronze). The two stale `kv://imperion/conn/*` rows (`gdap`, `docusign`, both `status=error`)
must be cleaned up / re-seeded via the GUI before those providers resolve.

## Future considerations

- Per-PR rollout of autotask / qbo / voyage / mileiq / docusign off the SecretStore (#318).
- Meta token-type reconciliation (FE page-send token vs LP system-user read token) before meta
  becomes registry-backed.
- LP-only vendors (cdw/easydmarc/datto/amazonbusiness) could later be promoted into the FE
  connection registry if/when they get provider rows.

## Cross-references

ADR-0028 (per-tenant credential resolution — the client-scope sibling this mirrors); ADR-0009
(vendorized vector contract + the #228 three-tier vendor resolution this supersedes for company
scope); frontend ADR-0103 (the `connection` credential registry); backend ADR-0034 (credential
storage). Epic #318; backend #385 (QBO refresh).
