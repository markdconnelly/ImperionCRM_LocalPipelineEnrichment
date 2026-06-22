# Curated Vault local-sync — rclone bisync runbook

_ImperionCRM_LocalPipelineEnrichment — `docs/operations`_

> Cross-repo parent epic: **ImperionCRM #1152** (Personal Knowledge Store) · This issue: **#306** ·
> Decision: **ADR-0114 §8** (vault substrate = per-owner Azure Blob container + a local synced
> markdown folder, over HTTPS — **no SMB/445, no VPN, no on-prem server**; the AFS/SMB approaches
> were rejected). Per-owner storage RBAC: **ImperionCRM #1176**.
>
> Part of the system-wide `/docs` standard (front-end `CLAUDE.md` §8). See [../../CLAUDE.md](../../CLAUDE.md).

## What this is

The **Curated Vault** is a per-owner Azure Blob container (`vault-<owner>` on the
`imperioncrmstorageprd` storage account) that the owner edits as a **local markdown folder**
in Obsidian or VS Code. This runbook documents the **bidirectional local-sync arm**: keeping the
local folder ⇄ blob container in step over HTTPS using [`rclone bisync`](https://rclone.org/bisync/).

There is **no file server, no SMB share (port 445), and no VPN**. rclone talks to the Blob
REST API over TLS; that is the only network path. Binaries dropped into the vault are synced
verbatim (byte-for-byte) alongside the markdown.

## Phasing

| Phase | Owner | Mechanism | Status |
| --- | --- | --- | --- |
| **Now** | owner-zero = **Mark** | a standalone `rclone bisync` **scheduled task** on Mark's Win11 box (this machine already runs LP), under **Mark's own Entra credentials** | this runbook; **Mark runs it** |
| **Later** | all 6 owners | promote the rclone job into a first-class LP collector — `Invoke-ImperionVaultSync` — on the standing LP schedule, with content-hash reconciliation feeding `personal_vault_file.content_hash` | fast-follow scaffold shipped (see [LP arm](#later-the-lp-arm)) |

> **The live rclone run is Mark-gated.** Standing up `rclone bisync` against the live
> `vault-mark` container requires Mark's own Entra credentials and runs on his box. The agent
> does **not** run `rclone bisync` or `--resync`, and does not touch the live container — this
> document is the procedure Mark follows.

---

## 1. Install rclone

On the Win11 box (PowerShell 7):

```powershell
winget install Rclone.Rclone        # or: choco install rclone
rclone version                       # confirm >= 1.66 (bisync is stable from 1.66+)
```

## 2. Configure the `azureblob` remote

The remote points at the `imperioncrmstorageprd` storage account. **Never embed an account key
or SAS token** — use Entra auth (`Never commit secrets`, `CLAUDE.md` §2/§8). Two auth options:

### Option A — `az login` token (interactive, simplest for owner-zero)

Mark holds `Storage Blob Data Contributor` on his own `vault-mark` container (ImperionCRM #1176).
rclone can ride the Azure CLI's logged-in identity:

```powershell
az login                             # Mark's Entra account, MFA as normal
```

`~/.config/rclone/rclone.conf` (or `%APPDATA%\rclone\rclone.conf`):

```ini
[vault]
type = azureblob
account = imperioncrmstorageprd
use_az = true                        ; use the Azure CLI's cached credential — no key/SAS on disk
```

> `use_az = true` makes rclone call the `az` credential chain. The token is short-lived and
> minted by `az`; nothing secret is written into `rclone.conf`.

### Option B — service principal / managed identity (unattended, the path the LP arm will use)

For a fully unattended scheduled task, authenticate as the cert-backed service identity rather
than Mark's interactive `az` session (the §6 token posture — no stored secret). With a client
**certificate** (preferred — matches `CLAUDE.md` §2; the cert is the credential, no client secret):

```ini
[vault]
type = azureblob
account = imperioncrmstorageprd
tenant = <ENTRA_TENANT_ID>           ; placeholder — fill from config, never commit
client_id = <SP_APP_ID>              ; placeholder
client_certificate_path = %ProgramData%\Imperion\vault-sync.pem   ; cert on disk, ACL'd to the task identity
```

Or with a managed identity (if the box is Azure-Arc-enrolled): `use_msi = true`, `msi_client_id = <UAMI>`.
**Key Vault note:** if a client secret is ever used instead of a certificate, it lives in the
SecretStore / Key Vault and is fetched at task start — never written into `rclone.conf` or passed
on a command line.

## 3. Bootstrap with `--resync` (one time, per owner)

`bisync` needs a baseline before it can sync bidirectionally. The **first ever** run uses
`--resync` to establish that baseline; **every subsequent run omits it**.

```powershell
# Local folder Mark edits in Obsidian/VS Code:
$Local  = "C:\Users\markd\ImperionVault"
$Remote = "vault:vault-mark"

# ONE-TIME baseline. --resync makes path1 (local) the source of truth and seeds path2 (blob).
# Confirm the local folder holds the canonical content BEFORE running this — resync can
# overwrite the side it treats as secondary.
rclone bisync $Local $Remote --resync --verbose
```

> **`--resync` is destructive on conflict** — it does not merge, it picks a winner. Run it once,
> deliberately, with the canonical content on the local side. After the baseline exists, never
> pass `--resync` again unless you are intentionally re-baselining (see [Conflicts](#failure--conflict-handling)).

## 4. Steady-state bisync + cadence

After the baseline, the recurring command is:

```powershell
$Local  = "C:\Users\markd\ImperionVault"
$Remote = "vault:vault-mark"

rclone bisync $Local $Remote `
  --conflict-resolve newer `        # on a two-sided edit, keep the newer file...
  --conflict-loser pathname `       # ...and keep the loser as `name.conflict-<ts>` (never silently dropped)
  --max-delete 25 `                 # safety brake: abort if a run would delete > 25 files (catches a bad mount)
  --check-access `                  # require a sentinel file on both sides — refuse to sync a half-mounted path
  --log-file "%ProgramData%\Imperion\logs\vault-bisync.log" `
  --log-format date,time
```

**Cadence:** every **15 minutes** for owner-zero (markdown is small, edits are interactive and
want a tight round-trip). The reconciliation is idempotent — an unchanged run is cheap and
no-ops. Tune per owner once the LP arm fans out.

## 5. Scheduled task (Win11)

Register under Mark's account "run whether logged on or not" (owner-zero uses Mark's own
credentials by design — this is *his* personal vault, not a service-identity collector):

```powershell
$action  = New-ScheduledTaskAction -Execute 'rclone.exe' `
  -Argument 'bisync C:\Users\markd\ImperionVault vault:vault-mark --conflict-resolve newer --conflict-loser pathname --max-delete 25 --check-access --log-file %ProgramData%\Imperion\logs\vault-bisync.log --log-format date,time'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)
Register-ScheduledTask -TaskName 'Imperion Vault Sync (owner-zero)' `
  -Action $action -Trigger $trigger -RunLevel Limited -Description 'rclone bisync vault-mark <-> local folder (#306)'
```

> Do **not** register this against `Invoke-ImperionVaultSync` — that cmdlet is the **not-yet-wired
> LATER-phase scaffold** (below). Owner-zero runs the raw `rclone bisync` task above.

## Failure & conflict handling

- **`--resync required` error.** Means no baseline (or a corrupted listing). Re-run the one-time
  `--resync` step **after confirming the local side is canonical**. This is the only time
  `--resync` is rerun.
- **Two-sided edit (conflict).** `--conflict-resolve newer` keeps the newer copy; `--conflict-loser
  pathname` preserves the older copy as `file.conflict-<timestamp>.md` so nothing is silently
  lost. Resolve by hand and delete the `.conflict-*` file.
- **`--max-delete` abort.** A run that wants to delete more than the brake (25) **stops without
  deleting** — almost always a missing/half-mounted local folder, not a real mass-delete. Fix the
  path, then re-run.
- **`--check-access` failure.** A required sentinel file (e.g. `RCLONE_TEST`) is missing on one
  side — rclone refuses rather than risk syncing against an empty/wrong target. Restore the
  sentinel on both sides.
- **Token expiry (Option A).** The `az` token lapses (~1h / on reboot). Re-run `az login`; for
  fully unattended operation prefer Option B (SP/cert or MSI), which the LP arm will use.
- **Concurrency.** Never run two bisyncs over the same pair at once — the 15-min repetition plus
  rclone's own lockfile guards this; a stuck lock after a crash clears with `rclone bisync ...
  --recover` (or remove the stale `.lck`).

## Event-driven upgrade path

Curator change-detection currently **polls** `personal_vault_file.content_hash` (front-end
migration 0169). **Blob Event Grid is the event-driven upgrade path** (ADR-0114 §8): once the
`vault-<owner>` containers emit `BlobCreated`/`BlobDeleted` events, the Curator reacts to those
events instead of polling, and this scheduled reconciliation becomes the **backstop** rather than
the primary change signal. That upgrade is out of scope for #306.

## Later: the LP arm

The fast-follow promotes the per-owner rclone job into a first-class LP collector,
**`Invoke-ImperionVaultSync`** (scaffold shipped in this PR at
`src/ImperionPipeline/Public/knowledge/Invoke-ImperionVaultSync.ps1`, currently **not wired** —
it throws `NotImplemented`). When built it will:

1. enumerate the configured owner roster (owner-zero `mark` first, then all 6 owners);
2. run `rclone bisync` per owner over one shared LP context on the standing LP schedule,
   authenticating as the cert-backed service identity (Option B — no stored secret, §2/§6);
3. hash each synced file with `Get-ImperionContentHash` and upsert
   `personal_vault_file.content_hash` (FE 0169) so the Personal Curator detects changes without
   re-reading every blob — idempotent, fail-closed per owner (one bad owner never blocks the rest).

**Prerequisites before wiring** (all human-gated, `CLAUDE.md` §2/§8):

- owner-zero must be **proven round-tripping in prod first** (issue #306 "Done when") — ship now,
  verify, then wire (the same ship-first/verify discipline as the merge cutover, ADR-0026);
- per-owner storage RBAC from **ImperionCRM #1176** in place for every owner;
- the **LP service identity's own grant** onto the `vault-<owner>` containers is a **new write
  capability** — an explicit, documented, human-approved Azure grant, recorded in `docs/security/`,
  never added for convenience;
- the **owner roster + per-owner local-folder/container mapping** lands as config with the build
  issue (not invented from PowerShell).

## Security notes

- **HTTPS only.** rclone reaches Blob over the TLS REST API — no SMB/445, no VPN, no inbound
  surface on this box (`CLAUDE.md` §1/§8).
- **No secrets on disk or in the repo. Never commit secrets.** Entra auth only (`az` token,
  cert, or MSI); no account key or SAS in `rclone.conf`, in a task argument, or in this doc —
  the values above are placeholders.
- **Per-owner RBAC isolation.** Each owner can read/write only its own `vault-<owner>` container
  (`Storage Blob Data Contributor` scoped to that container, ImperionCRM #1176). No owner — and
  no single sync run — can reach another owner's vault.
- **Idempotent + auditable.** bisync is a converging reconciliation; every run logs to
  `vault-bisync.log` with the date/time format above. The LP arm will additionally emit the
  module's structured JSON log lines (`Write-ImperionLog`).

## See also

- [`change-detection.md`](change-detection.md) — the content-hash + watermark mechanism the LP arm reuses.
- [`scheduled-task-registry.md`](scheduled-task-registry.md) — the cadence registry the LP arm task joins once wired.
- [`secret-rotation.md`](secret-rotation.md) · [`certificate-rotation.md`](certificate-rotation.md) — the cert/secret the Option B auth depends on.
