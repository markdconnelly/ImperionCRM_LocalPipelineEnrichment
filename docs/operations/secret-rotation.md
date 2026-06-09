# Secret rotation runbook

The SecretStore holds **source API keys** (Autotask, IT Glue, Apollo, KQM, DocuSign,
website) and **embedding/LLM provider keys**. It holds **no DB password** (Entra token,
ADR-0003) and **no app client secret** (cert auth, ADR-0002).

## Rotate a source/provider key
1. Mint the new key in the source system (keep the old one valid during overlap).
2. `Set-Secret -Name <key-name> -Secret <new>` into the SecretStore.
3. Run the affected task once; confirm success in the logs.
4. Revoke the old key in the source system.

## Vault hygiene
- Names are stable, documented constants (see `config/secret-names.example.psd1`).
- Never echo secrets to logs or task arguments.
- The vault is unlocked only at task start via the cert (CMS) and re-locked on exit.

## Rotate the vault password
Re-run the bootstrap: generate a new vault password, `Set-SecretStorePassword`, then
`Protect-CmsMessage` it to the cert and replace the CMS blob.
