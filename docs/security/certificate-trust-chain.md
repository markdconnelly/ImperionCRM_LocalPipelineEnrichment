# Certificate trust chain

The unattended security model hangs off **one machine certificate** (ADR-0002). Treat it as
the crown jewel.

```
Scheduled Task  (runs as a dedicated gMSA / service account — never an interactive user)
  └─ Certificate  (Cert:\LocalMachine\My; non-exportable private key; ACL'd to the task identity only)
       ├─ (a) Opens the SecretStore
       │       CMS blob (vault password encrypted to the cert)  ──Unprotect-CmsMessage──▶ Unlock-SecretStore
       │       SecretStore yields: the node app credential (end-state ADR-0029) + the few sources not yet on DB→KV
       └─ (b) Is the node app credential — INFRA/BOOTSTRAP tokens only (ADR-0030)
               Get-MsalToken -ClientCertificate  ──▶ app-only tokens:
                 • Azure Key Vault  (Key Vault Secrets User — read the credential registry's blobs)
                 • Azure Storage    (data-plane write — staging/landing)
                 • Azure PostgreSQL (short-lived token, no stored password — ADR-0003)
```

> **The cert SP reads NO tenant data (ADR-0030).** Microsoft Graph (365) **and** Azure ARM are
> read per tenant via the per-client onboarding app, whose credential is resolved from the
> `connection` registry → Key Vault ([`credential-resolution.md`](credential-resolution.md)).
> The cert SP holds **no** Graph or ARM data-read grant — it exists only to mint the Key Vault,
> Storage, and Postgres bootstrap tokens. This is the change from the earlier model where the
> cert SP itself authenticated Graph/ARM.

## Controls
- **Non-exportable key**, generated/stored in `LocalMachine\My`; read ACL granted to the
  task identity only (`icacls` / `Set-Acl` on the key container).
- **No plaintext secret on disk** — the vault password exists only as a CMS blob decryptable
  by the cert; tokens are minted per run and never persisted.
- **Dedicated run-as identity** with "log on as a batch job"; not Mark's account.
- **Monitoring:** cert expiry is surfaced by the relationship-health task; rotate before
  expiry (see [certificate-rotation.md](../operations/certificate-rotation.md)).
- **No inbound surface** — outbound calls only; nothing listens.

## Blast radius if the cert is stolen
Reduced by ADR-0030: the cert SP can read Key Vault, write Storage, and connect to Postgres
(table-scoped) — but it **cannot read 365 or enumerate Azure resources**, because tenant data
is reached only via the registry-resolved onboarding apps, not this cert. Mitigation: rotation,
ACLs, least-privilege DB role, the read-only-by-default grant (ADR-0002), and keeping no
tenant-data grant on the cert SP (ADR-0030).
