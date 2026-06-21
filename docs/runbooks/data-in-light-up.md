# Data-in light-up runbook — "integrated on paper" → "data flowing in prod"

The single operator playbook to take a client (or Imperion itself, **client-zero**) from
*integrated on paper* to *real rows in prod*: populate the credential registry, enable the
collectors, run a full collection, run the LP-owned merges, then gold re-sync + vectorization
so the agent can ground on it.

> **Why this exists.** The cross-repo inventory (2026-06-21 board) confirmed the pipeline is
> **~90% built** — ~60 bronze collectors already merge to silver. The blocker to real data is
> **operational, not code**: the credential registry is **empty in prod** and most collectors
> are dormant. This is the highest-value "tomorrow" deliverable. (Issue #278; composes #101
> gold re-sync + #102 host provisioning.)

This page is the **orchestration spine** — it sequences work owned by deeper docs and **links,
never restates**:

- Per-client M365/Azure app + consent → [`operations/client-tenant-onboarding.md`](../operations/client-tenant-onboarding.md)
- The as-built task catalog with every gating note → [`operations/scheduled-task-registry.md`](../operations/scheduled-task-registry.md)
- The source → cmdlet → bronze map → [`collector-inventory.md`](../collector-inventory.md)
- Per-tenant credential resolution → [ADR-0028](../decision-records/ADR-0028-provider-agnostic-per-tenant-credential-resolution.md) · front-end ADR-0103 (the `connection` registry)
- Gold + vectors → [`vectorization-to-gold.md`](../vectorization-to-gold.md)

> **Security (CLAUDE.md §2/§3/§8).** Onboarding a tenant is a **security event**. **Never
> commit secrets** — every credential value lives in Key Vault, custodied server-side; this
> runbook handles only *names*, *thumbprints*, and *aggregate counts*. All verification output
> is **count-only, no row-level PII**.

---

## ⚠️ Mark-gated stages (do not self-serve)

Three things in this runbook require Mark and are called out inline where they occur. Stage the
rest of the work right up to each gate, then stop:

| Gate | What | Where |
|---|---|---|
| **G1 — populate the registry** | Entering real client credentials into the GUI (KV custody) is data entry on production secrets. | Step 1 |
| **G2 — prod-apply pending migrations** | `0150` (`auth_method` += `api_key`, UniFi rows) · `0151` (`connection.provider_config` jsonb) · the UniFi bronze `unifi_devices` migration — all merged, **none prod-applied**. Each `migrate.mjs` apply needs an explicit Mark turn-word. | Step 2 (UniFi/QBO branches) |
| **G3 — service-identity shell** | The collectors run as `svc-imperion` (DPAPI SecretStore); `markd` is non-admin and can't enumerate/trigger the service tasks. On-prem host provisioning is #102. | Steps 3–5 |

Registry state in prod (verified 2026-06-20): `account_tenant` = 1 row (home tenant only),
`connection` = 7 rows (all `company`/`user` scope), **0 client rows**. Multi-tenant estate is
gated on registry **data** + the migrations above, not on code.

---

## Step 0 — Pre-flight (per host)

1. Host is provisioned and the module is current — pull + reinstall `ImperionPipeline` on the
   home server so it carries the latest resolver/merge fixes (the bring-up checklist is
   [`deployment/unattended-bringup.md`](../deployment/unattended-bringup.md); #102).
2. Confirm the identity chain is alive: `Initialize-ImperionContext` (or
   `Initialize-ImperionUnattended` under the service account) connects to prod as
   `imperion-localpipeline` via the cert-minted token. The master cert SP holds **Key Vault
   Secrets User** — it reads each client's credential and polls *as the client*.
3. Pick the **scope** for this run: a managed **client**, or **Imperion itself** (client-zero —
   identical path, no special-casing, ADR-0028).

---

## Step 1 — Populate the credential registry  ⛔ G1

For each source the client uses, land a **Key Vault-custodied** credential and a `connection`
registry row. The GUI (Settings → Credentials) custodies the secret server-side and writes the
row; the pipeline resolves it at run time via `Resolve-ImperionTenantCredential -AccountId
-Provider [-TenantId]` (cert → `@{ClientId;CertThumbprint}`, secret → `@{ClientId;ClientSecret}`,
api_key → `@{ApiKey}`). KV names follow `conn-<scope>-<provider>[-<tenantId|userId>]`.

**Per-source checklist** — each row becomes a `connection` (scope · `account_id` · auth):

| Source | Provider / scope | How to seed | Auth | Notes |
|---|---|---|---|---|
| **M365 / Entra / Intune / Defender** | `m365` · client | Run [`build/New-ImperionClientOnboardingApp.ps1`](../../build/New-ImperionClientOnboardingApp.ps1) as the tenant's Global Admin → paste app id + secret/thumbprint into **Settings → Credentials** (client M365 form) → map tenant in **Settings → Tenant mapping** (`account_tenant`). | cert or secret | Per-client app, read-only ([`client-tenant-onboarding.md`](../operations/client-tenant-onboarding.md)). App id on `client_id` (mig 0147). Don't widen the home SSO app. |
| **Azure ARM (cloud / DNS / Sentinel)** | `azure` · client | Same per-client app where ARM Reader is granted; tenant mapping is shared with M365. | cert or secret | Cloud-resource sweep fans out over `account_tenant`. |
| **Autotask** | `autotask` · company | Settings → Credentials (company). | API key | One company cred; already present in prod registry. |
| **IT Glue** | `itglue` · company | Settings → Credentials (company). | API key | Already in prod registry. |
| **QBO** | `qbo` · company | Seed `qbo-access-token` + `qbo-realm-id`. | OAuth | **Standing blocker** — needs the QBO app registration (Mark). |
| **KQM (Kaseya Quote Manager)** | `kqm` · company | Seed `KQM-API-Key`. | API key | URLs are secret-bearing (`?apikey=`) — never logged. |
| **Datto RMM / BCDR** | company | Seed `Datto-RMM-API-Key` / `Datto-BCDR-API-Key`. | API key → bearer | Bronze migration 0119 already applied. |
| **myITprocess** | company | Seed `myITprocess-API-Key`. | `api_token` header | |
| **Meta (FB / IG)** | `meta` · company | Seed the Meta Business token. | OAuth | Already live in prod (54 posts / 89 DMs verified). |
| **DNS** | via `azure` + OS resolver | No secret for the public-resolve plane; zone-read uses the ARM cred. | — | ADR-0063. |
| **UniFi** | `unifi` · client | Settings → Credentials (client UniFi form): console\|cloud + `controllerHost` if console. | API key | ⛔ **G2** — rows blocked until `0150` (`api_key` CHECK) + `0151` (`provider_config`) prod-applied. |
| **DocuSign / Plaud / Amazon / CDW / Dark Web ID / Telivy** | company | Seed the named KV secret per [`scheduled-task-registry.md`](../operations/scheduled-task-registry.md). | varies | All dormant-until-credential; optional for the wedge. |

> **Stop at G1** until Mark has entered the real credentials. Everything below is safe to stage
> against an empty registry — the collectors fail **closed** (log + exit) on a missing row.

---

## Step 2 — Enable + verify the scheduled tasks  ⛔ G2 (UniFi/QBO bronze)

Most `.task.ps1` files exist but are **not registered** — only the ~13-cmdlet `$tasks` array in
`Register-ImperionTask` is live on the host. To light a source up:

1. **Register** (run once, elevated, under the service identity):
   `Register-ImperionTask` is idempotent — re-run it to (re)register the catalog, then
   register any per-`(source,entity)` task file not in the default array (pattern in
   [`scheduled-tasks/README.md`](../../scheduled-tasks/README.md)).
2. **Confirm the bronze table exists.** Each collector fails loudly on a missing table (the
   front end owns schema). Tables flagged *pending FE migration* in the registry stay dormant
   until applied — **UniFi `unifi_devices` is the open one (⛔ G2)**; QBO finance tables rode
   migration 0120 (applied).
3. **Run one full collection on demand:** `Start-ScheduledTask -TaskName '<task>' -TaskPath
   '\Imperion\'` (or invoke the `.task.ps1` directly under the service shell). Watch the
   structured JSON in `logs/` — every run emits `{run id, source, counts, duration, cost}`,
   **counts only, no row content**.

Tune cadence per source via the `integrations/<source>.md` doc — no code change.

---

## Step 3 — Run the LP-owned bronze → silver merges  ⛔ G3

Whichever plane *ingests* a source owns its merge (ADR-0026). This repo runs its merges on-prem,
**after** that source's collectors land bronze; the cloud Pipeline keeps only the
live/webhook-driven `website_*` sweep + DocuSign (do **not** run those here).

| Merge cmdlet | Silver target | Run after |
|---|---|---|
| `Invoke-ImperionPostureMerge` | `posture_policy` + `tenant_posture` | SecureScore + PolicySync |
| `Invoke-ImperionPostureSnapshot` | `posture_snapshot` (quarterly self-gate) | PostureMerge |
| `Invoke-ImperionM365DirectoryMerge` | `contact_enrichment.directory_groups` | m365 users + entra-groups + group-members |
| `Invoke-ImperionCloudAssetMerge` | `cloud_asset` (CMDB) | the `azure/cloud-resources` sweep |
| `Invoke-ImperionDnsMerge` | `dns_domain` | dns-zones + dns-resolve |
| `Invoke-ImperionMetaMerge` | `meta_*` / `instagram_*` silver | Meta collectors |
| `Invoke-ImperionUniFiMerge` *(pending, LP #284)* | `device` (network-infra class) | UniFi collector |

Merges are idempotent (set-based replace / `ON CONFLICT` upsert) and **dormant-safe** — they log
+ exit if their bronze is empty or the silver migration is unapplied. Expect silver rows in
`account` / `contact` / `device` / `ticket` / `contract` / `time_record` after a clean pass.

---

## Step 4 — Gold re-sync + vectorization  (#101)

Once silver has new rows, refresh the gold knowledge layer so the agent can ground on it:

```powershell
Invoke-ImperionKnowledgeSync -Vectorize    # nightly task 'Imperion-Knowledge' @ 04:30
```

Composes `knowledge_object` from silver (incl. FB/IG `social`), chunks (v1), and embeds via
**Voyage @ 1024** (ADR-0009). **Chunk-hash idempotent** — a re-sync over unchanged content does
**not** re-bill embeddings; only new/changed rows cost. Full lifecycle + citation views:
[`vectorization-to-gold.md`](../vectorization-to-gold.md). (This is #101 — the operator gold
re-sync; run it after the first full collection of a newly onboarded client.)

---

## Step 5 — Verify (aggregate only, no PII)

Confirm data landed without copying any row-level personal data into issues/PRs/logs
(CLAUDE.md §8). Use count/`max(collected_at)` shapes against the read-only DB, or read the
per-run JSON logs. Record an aggregate verification table:

| Source | Bronze table | Rows (count) | Last run / `max(collected_at)` | Silver reached? |
|---|---|---|---|---|
| Autotask contracts | `autotask_contracts` | _n_ | _ts_ | `contract` ✓/✗ |
| Autotask tickets | `autotask_tickets` | _n_ | _ts_ | `ticket` ✓/✗ |
| M365 users/devices | `m365_contacts` / `m365_devices` | _n_ | _ts_ | `contact` / `device` ✓/✗ |
| IT Glue | `itglue_*` | _n_ | _ts_ | `account` / `device` ✓/✗ |
| Datto RMM/BCDR | `datto_rmm_devices` / `datto_bcdr_backups` | _n_ | _ts_ | `device` ✓/✗ |
| Azure cloud | `cloud_resources` | _n_ | _ts_ | `cloud_asset` ✓/✗ |
| Posture | `posture_policy` | _n_ | _ts_ | `tenant_posture` ✓/✗ |
| Meta | `meta_*` / `instagram_*` | _n_ | _ts_ | silver ✓/✗ |
| UniFi *(post-G2)* | `unifi_devices` | _n_ | _ts_ | `device` ✓/✗ |
| Gold | `knowledge_object` | _n_ | _ts_ | vectors ✓/✗ |

A source at **0 rows with a clean (non-erroring) run** = dormant-on-credential, expected before
its G1/G2 gate clears. An **erroring** run is a real failure — check the JSON log's error field
(never the row content).

---

## Exit criteria

- [ ] Every in-scope source has a `connection` row (scope · `account_id` · auth) — G1 cleared.
- [ ] Each enabled task registered and one full collection landed bronze.
- [ ] LP-owned merges produced silver (`account` / `contact` / `device` / `ticket` / `contract`
      / `time_record`).
- [ ] Gold re-sync + vectorization run (#101); `knowledge_object` + vectors refreshed.
- [ ] Aggregate verification table recorded — **no PII**.

> Per-client repeat: run Steps 1→5 per onboarded client (and once for Imperion as client-zero).
> One worktree per session (§10.1); no secrets in the repo (§2).
