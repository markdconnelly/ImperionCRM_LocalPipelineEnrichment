# Certificate trust chain

The unattended security model hangs off **one machine certificate** (ADR-0002). Treat it as
the crown jewel.

```
Scheduled Task  (runs as a dedicated gMSA / service account — never an interactive user)
  └─ Certificate  (Cert:\LocalMachine\My; non-exportable private key; ACL'd to the task identity only)
       ├─ (a) Opens the SecretStore
       │       CMS blob (vault password encrypted to the cert)  ──Unprotect-CmsMessage──▶ Unlock-SecretStore
       │       SecretStore yields: source API keys, embedding/LLM provider keys
       └─ (b) Is the Entra app credential
               Get-MsalToken -ClientCertificate  ──▶ app-only tokens:
                 • Microsoft Graph  (read-only: Application.Read.All / Directory.Read.All; per-client onboarding app per client tenant, ADR-0018)
                 • Azure ARM        (read-only: Reader; write only to Storage/PG/KeyVault)
                 • Azure PostgreSQL (short-lived token, no stored password — ADR-0003)
```

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
Read-only across Azure/365 (cannot mutate the prod RG), plus write to Storage/PG/KeyVault
and whatever the SecretStore holds. Mitigation: rotation, ACLs, least-privilege DB role,
and the read-only-by-default grant (ADR-0002).
