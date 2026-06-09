# Certificate rotation runbook

The certificate is the root of trust (ADR-0002). Rotate before expiry; a stolen or expiring
cert must be replaceable without downtime.

## Rotate (zero-downtime, overlap two certs)
1. **Generate** the new cert (non-exportable key) in `Cert:\LocalMachine\My`.
2. **Grant** private-key read to the task identity (`icacls`/`Set-Acl`).
3. **Upload** the new public cert to the Entra app registration (now two valid creds).
4. **Re-protect** the SecretStore password to the **new** cert (`Protect-CmsMessage`),
   keeping the old CMS blob until cutover.
5. **Verify** a task can `Unprotect-CmsMessage` + `Unlock-SecretStore` and mint Graph/ARM/PG
   tokens with the new cert.
6. **Cut over** task config to the new thumbprint; run one of each task.
7. **Remove** the old cert from the Entra app and delete the old CMS blob + old cert.

## Emergency (suspected compromise)
- Immediately **remove the cert from the Entra app** (kills app auth) and **disable the
  scheduled tasks**.
- Rotate any source API keys / provider keys held in the SecretStore.
- Review audit logs for the SP's recent Graph/ARM/PG activity.

## Monitor
The relationship-health task also checks **cert expiry** and surfaces it ahead of time.
