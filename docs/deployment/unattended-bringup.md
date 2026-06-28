# Unattended bring-up runbook (concrete)

Turnkey checklist to take the pipeline from "auth/DB/schema proven" to "running unattended on
the home server." Values below are the **real, verified** ones for this system (2026-06-09).
Generic background is in [README.md](README.md); the trust model is `CLAUDE.md` §2.

## Already done (verified against prod `imperioncrm-pg-prd`)
- **Schema:** migrations `0038`–`0043` applied (all bronze/golden tables + views + the
  `darkwebid` enum present).
- **Identity + grants:** PG role **`imperion-localpipeline`** created via `pgaadauth`, mapped to
  the cert-backed SP **"Imperion CRM"** (`type=service`, non-admin), granted
  `SELECT/INSERT/UPDATE` on the 42 tables this repo writes (migration `0044`; **no DELETE**).
- **Live chain proven:** cert → `ossrdbms` token → connect as `imperion-localpipeline` → INSERT
  (rolled back) → DELETE denied (`42501`). Re-runnable via `build/Test-ImperionUnattendedChain.ps1`.

## Known identifiers (no secrets — safe to record)
| Thing | Value |
| --- | --- |
| Entra app (pipeline SP) | **Imperion CRM** — appId `46f1077b-c93f-42da-abd4-192da13781ac` |
| SP object id | `d944e180-cb77-45cc-b683-375630e4efbd` |
| Certificate | thumbprint `F860A0D53376DBFD10DD9C2E53C118366832EFCC` (`CN=ImperionCRM-WebApp-EntraAuthCert`, exp 2027-06-06) |
| Partner tenant | `49307c12-1bb7-42e4-9c7c-43d2850bd8c6` |
| Postgres role | `imperion-localpipeline` |
| PG host / db | `imperioncrm-pg-prd-cus.postgres.database.azure.com` / `imperioncrm` |

## Done on the server this session (as `MARKSWORKPC\markd`, non-elevated)
- Staged `C:\ProgramData\Imperion\` (+ `logs`, `lib`) and wrote the real **`pipeline.config.psd1`**
  (values above); seeded `secret-names.psd1`.
- Pulled **Npgsql 8.0.3** + its `Microsoft.Extensions.Logging.Abstractions` dep into
  `…\lib\` and installed the module (CurrentUser scope) for validation.
- **Proved the shipping module DB code live**: `Open-ImperionDbConnection` +
  `Invoke-ImperionDbQuery` connected to prod as `imperion-localpipeline` (cert-minted token) and
  read `autotask_contracts`. So the PowerShell path — not just node — is verified end to end.

## ✅ Interim mode active (2026-06-09): `-SkipSecretStore` + Key Vault fallback

Until the service identity exists (decision below), the pipeline runs **interactively as
`markd`** with `Initialize-ImperionContext -SkipSecretStore`: the markd-profile cert mints
all tokens, and Key-Vault-backed secrets work (the cert SP was granted **Key Vault
Secrets User** on `kv-imperioncrm-prd` 2026-06-09 — the CLAUDE.md §2 grant, previously
missing). The Voyage embedding key resolves SecretStore-first → **Key Vault
`Voyage-Embedding-API-Key`** (ADR-0009), so vectorization runs without a local vault.
SecretStore-only secrets (Autotask/IT Glue/Telivy source keys) stay unavailable until
step 5. **Do NOT create the `ImperionStore` vault under `markd`** — SecretStore config is
per-user-singleton and markd has personal vaults (AIApp, MarksWorkstationSecureVault);
reconfiguring would risk them. The vault belongs to the service identity's profile.

## ✅ Identity model DECIDED (2026-06-11, ADR-0012): local account `.\svc-imperion`
`MARKSWORKPC` is a workgroup machine, so CLAUDE.md §2's "gMSA (preferred)" is **not possible**.
Mark's call: the documented fallback, a **dedicated local service account `.\svc-imperion`**
(ADR-0012 records the deviation). Create it with the elevated run-once helper:
```powershell
.\build\New-ImperionServiceAccount.ps1 -DenyInteractiveLogon   # prompts for the password
```
(creates the account, grants "Log on as a batch job", optionally denies console logon).
Consequences for the steps below: the cert private key is ACL'd to `.\svc-imperion`; the
SecretStore vault is **per-user-profile**, so `Initialize-ImperionUnattended` must run **as
`.\svc-imperion`**, not as markd; and task registration uses
`Register-ImperionTask -TaskCredential (Get-Credential '.\svc-imperion')` — a local account
needs stored credentials (the gMSA no-password path stays available for a future
domain-joined host). A password change requires re-running `Register-ImperionTask`.

## Remaining steps (host packaging — run on the server, ELEVATED, as/for the chosen service account)

1. **Install module + deps** (admin pwsh 7):
   ```powershell
   .\build\Install-ImperionModule.ps1 -Scope AllUsers
   .\build\Install-ImperionDependencies.ps1     # Npgsql -> %ProgramData%\Imperion\lib, + MSAL.PS/SecretStore
   ```

2. **Certificate into `LocalMachine\My`** (a gMSA task can't read a user-store cert). The cert is
   currently in `CurrentUser\My`. Either export+import (if its key is exportable) or re-issue into
   the machine store, then ACL the private key to the task identity:
   ```powershell
   # import (example, if you have the PFX):
   Import-PfxCertificate -FilePath imperion.pfx -CertStoreLocation Cert:\LocalMachine\My -Password (Read-Host -AsSecureString)
   # grant the gMSA read on the private key (no other principal):
   #   use Set-Acl / icacls on the key container — see docs/operations/certificate-rotation.md
   ```
   Confirm the **same thumbprint** ends up in `LocalMachine\My` and is registered on the
   "Imperion CRM" app (it already is).

3. **Local service account** (ADR-0012): run `.\build\New-ImperionServiceAccount.ps1
   -DenyInteractiveLogon` (elevated) — creates `.\svc-imperion` with a prompted password and
   grants **"Log on as a batch job"** via secedit (no secpol.msc clicking). Then grant it the
   private-key read from step 2. Tasks run "whether logged on or not" as this identity.
   (`Initialize-ImperionUnattended` in step 5 must be run **as this account**, since the
   SecretStore vault lives in its profile.)

4. **`%ProgramData%\Imperion\pipeline.config.psd1`** — the installer seeds the template; set:
   ```powershell
   @{
       CertThumbprint  = 'F860A0D53376DBFD10DD9C2E53C118366832EFCC'
       ClientId        = '46f1077b-c93f-42da-abd4-192da13781ac'
       LocalTenantId   = '49307c12-1bb7-42e4-9c7c-43d2850bd8c6'   # renamed from PartnerTenantId (#329); loader still reads the old key for one release
       SecretStoreAuthentication = 'None'   # DPAPI unlock (ADR-0002 amendment) — the Entra cert lacks the Document Encryption EKU CMS needs
       CmsPasswordPath = 'C:\ProgramData\Imperion\vault.cms'   # ignored when SecretStoreAuthentication='None'
       SecretVault     = 'ImperionStore'
       LogDirectory    = 'C:\ProgramData\Imperion\logs'
       NpgsqlDllPath   = 'C:\ProgramData\Imperion\lib\<...>\lib\net8.0\Npgsql.dll'  # path printed by the deps installer
       Db = @{ Host='imperioncrm-pg-prd-cus.postgres.database.azure.com'; Database='imperioncrm'; Username='imperion-localpipeline'; Port=5432 }
       ITGlue   = @{ BaseUri='https://api.itglue.com' }
       KeyVault = @{ VaultUri='https://kv-imperioncrm-prd.vault.azure.net' }
   }
   ```

5. **SecretStore unlock — DPAPI, not CMS** (ADR-0002 amendment, 2026-06-17). The Entra cert
   (`F860A0D5…`) carries only Client/Server Auth EKUs, so `Protect-CmsMessage` cannot use it;
   the SecretStore is configured for **`-Authentication None`** (DPAPI, bound to the
   `svc-imperion` profile) and holds **API keys only**. The vault lives in `svc-imperion`'s
   profile, so `Initialize-ImperionUnattended` must run **as `svc-imperion`** — and because
   that account is deny-interactive-logon, drive it with a one-shot scheduled task:
   ```powershell
   # AS svc-imperion (one-shot scheduled task, RunLevel Limited, x64 pwsh):
   Initialize-ImperionUnattended -CertThumbprint 'F860A0D5…' -Authentication None
   #   -> Reset-SecretStore -Authentication None (non-interactive); NO CMS blob, NO doc-enc cert.
   #   (Set-SecretStoreConfiguration would HANG a session-0 task on a confirm prompt — hence Reset.)
   # The cert private-key ACL to svc-imperion is granted SEPARATELY as admin (step 2 / Set-Acl).
   ```
   Then **load source API keys** — also **as `svc-imperion`** (the vault is in its profile):
   ```powershell
   Copy-Item config\secret-names.example.psd1 C:\ProgramData\Imperion\secret-names.psd1
   # Set-Secret for each source the node polls directly (SecretStore titles per secret-names):
   #   Autotask-API-TrackingIdentifier / -Username / -Password, ITGlue-API-Key, Telivy-API-Key …
   # (Dark Web ID is NOT a SecretStore secret — read from Key Vault conn-company-darkwebid.)
   ```

6. **Verify the full chain on the host:**
   ```powershell
   pwsh -File build\Test-ImperionUnattendedChain.ps1     # expect all stages PASS
   ```

7. **Register tasks** — ONE elevated run registers all nine (ADR-0012 credential mode;
   prompts for the svc-imperion password, stores it with Task Scheduler):
   ```powershell
   Register-ImperionTask -TaskCredential (Get-Credential '.\svc-imperion')
   ```

8. **First real load:** run one task by hand and inspect `logs/imperion-<date>.jsonl` for the
   `Metric` line (scanned/inserted/updated/unchanged), then confirm rows in prod bronze.

## What can't be pre-done from a dev box
Steps 2–3 (cert into `LocalMachine` + gMSA + key ACL) and the elevated installs (1, 5) are
hands-on on the server and are §2/§8 actions. Everything's parameter-ready above.
