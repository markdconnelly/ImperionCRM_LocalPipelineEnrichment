# Secret rotation runbook

The SecretStore holds **source API keys** (Autotask, IT Glue, Apollo, KQM, DocuSign,
website, EasyDMARC, QBO, **Datto RMM, Datto BCDR, myITprocess**). It holds **no DB password**
(Entra token, ADR-0003), **no app client secret** (cert auth, ADR-0002), and — since
front-end ADR-0129 §8 (#406) — **no embedding key**: the Voyage key is the platform-scope AI
credential read from Key Vault `conn-platform-voyage` (see the reconcile step below).

The RMM / managed-estate keys (issue #195, ADR-0018) are three MSP-wide vendor keys —
SecretStore titles `Datto-RMM-API-Key`, `Datto-BCDR-API-Key`, `myITprocess-API-Key`
(config keys `DattoRmmApiKey` / `DattoBcdrApiKey` / `MyItProcessApiKey`; Key Vault originals
of the same titles are the fallback). They follow the same mint→overlap→`Set-Secret`→run→
revoke procedure below. Datto RMM exchanges its API key for a short-lived bearer at call
time (no separate stored token to rotate); rotating the API key rotates the whole chain.

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

## One-time: reconcile the Voyage key to `conn-platform-voyage` (front-end ADR-0129 §8, #406)

**Mark-gated, one-time.** The embedding key read repointed from the mis-named starter secret
to the platform-scope registry name `conn-platform-voyage` (folds #389). The key VALUE is
unchanged — only its Key Vault name moves — so this is a copy, not a rotation (no Voyage-side
mint/revoke). Until done, the vectorizer reads a name that does not exist yet and fails loudly.

1. Copy the existing starter key value into the canonical platform name (cert SP needs Key Vault
   Secrets **Officer/Set** for this step; the run-time cert SP only needs **User/Get**):
   ```powershell
   $v = Get-ImperionKeyVaultSecret -Name 'Voyage-Embedding-API-Key'   # the starter secret
   Set-AzKeyVaultSecret -VaultName <kv> -Name 'conn-platform-voyage' -SecretValue (ConvertTo-SecureString $v -AsPlainText -Force)
   ```
   (Equivalently, seed it on the front-end Connections **platform card** — same canonical name,
   validate-before-write; either path lands `conn-platform-voyage`.)
2. Update the host `config/secret-names.psd1`: `EmbeddingProviderKeyVaultSecret = 'conn-platform-voyage'`
   and **remove** the retired `EmbeddingProviderKey` line (no SecretStore mirror any more).
3. Run `Invoke-ImperionKnowledgeSync -Vectorize` once; confirm success + a non-zero token
   count in the logs.
4. Once verified, **delete** the retired secrets: Key Vault `Voyage-Embedding-API-Key` and the
   SecretStore `embedding-provider-key` (`Remove-Secret -Name embedding-provider-key`).
