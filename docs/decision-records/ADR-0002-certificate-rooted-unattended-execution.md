# ADR-0002: Certificate-rooted unattended execution + read-only-by-default grant

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-08 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | — |

## Problem

Scheduled tasks run with no human at the keyboard, yet must unlock a local secret store and
authenticate to Microsoft Graph / Azure. We need an unattended credential model that is not
a plaintext password on disk, and a privilege posture that survives the system's "Mythos
Proof" threat model (assume credential theft).

## Options considered

1. **Stored vault password / `-Authentication None` DPAPI binding.** Works, but the unlock
   is bound only to the machine/account, not to a rotatable, ACL-controllable credential.
2. **Certificate-rooted (chosen).** One machine certificate is the root of trust.

## Decision

A single non-exportable machine certificate (`Cert:\LocalMachine\My`, private key ACL'd to
the task identity) does two jobs:
- **(a) Opens the SecretStore** — the vault password is stored as a CMS message encrypted
  to the cert (`Protect-CmsMessage`); at task start `Unprotect-CmsMessage` (needs the
  private key) → `Unlock-SecretStore`. *(Fallback: `-Authentication None` DPAPI binding,
  documented if CMS proves impractical.)*
- **(b) Is the Entra app credential** — cert-based app-only auth (`Get-MsalToken
  -ClientCertificate`) for Graph/ARM. No client secret needed.

Tasks run under a dedicated **gMSA / service account**, never Mark's interactive account.

**Grant model (agreed): read-only by default.** The cert app holds broad **`Reader`**
across Azure and **read-only GDAP** into 365. The only write / data-plane grants are the
three the pipeline needs: **Azure Storage**, the **shared PostgreSQL** (table-scoped role),
and **Key Vault** (`Secrets User`). Any new write capability is an explicit,
human-approved grant — never added for convenience. (This replaced an earlier, far broader
"Owner over the resource group" idea.)

## Consequences

### Security impact

- **Security impact:** compromise of the cert = the blast radius. Mitigated by:
  non-exportable key, ACL to the task identity only, read-only-by-default Azure/365 posture
  (a stolen cert cannot mutate the prod RG), and planned rotation (see
  [cert rotation runbook](../operations/certificate-rotation.md)).

### Cost impact

- **Cost impact:** none material.

### Operational impact

- **Operational impact:** cert lifecycle + ACLs become an operational concern; the gMSA
  must have "log on as a batch job."

## Future considerations

- **Future considerations:** narrow the Storage/DB/KV grants further per actual usage;
  add cert-expiry monitoring to the relationship-health task.

## Amendment (2026-06-17) — SecretStore unlock activated as the DPAPI fallback

The Decision's primary unlock path (CMS-encrypted vault password) requires a certificate with
the **Document Encryption** EKU (`1.3.6.1.4.1.311.80.1`), which `Protect-CmsMessage` enforces.
The deployed Entra app certificate (`CN=ImperionCRM-WebApp-EntraAuthCert`, thumbprint
`F860A0D5…`) carries only **Client/Server Authentication** EKUs, so it cannot encrypt the CMS
blob. Rather than introduce a second (Document Encryption) certificate, we **activate the
documented fallback**: `Set-SecretStoreConfiguration -Authentication None -Interaction None`.

Resulting model:
- The **SecretStore holds API keys only** and is unlocked by **DPAPI binding to the
  `.\svc-imperion` task-identity profile** — no vault password, no CMS file, no doc-enc cert.
  `Initialize-ImperionUnattended -Authentication None` must therefore run **as the task
  identity** (the store lives in its profile).
- The **certificate remains non-exportable in `Cert:\LocalMachine\My`**, ACL'd to
  `.\svc-imperion`, and is used **solely for token minting** (job (b) — Graph/ARM/Key
  Vault/Postgres via `Get-MsalToken -ClientCertificate`). Job (a) is now DPAPI, not the cert.

Security delta vs. the CMS model: the unlock gate is the OS account boundary (DPAPI) rather
than a cert-encrypted password, i.e. "slightly weaker" per the original fallback note — but
the cert's private key stays non-exportable, so the crown-jewel exposure is unchanged. The
config flag is `SecretStoreAuthentication` (`pipeline.config.psd1`); `'Password'` preserves the
original CMS path for any future host whose cert has the Document Encryption EKU.

## Cross-references

This repo `CLAUDE.md §2`, §8; [security/certificate-trust-chain.md](../security/certificate-trust-chain.md),
[security/least-privilege-grants.md](../security/least-privilege-grants.md).
