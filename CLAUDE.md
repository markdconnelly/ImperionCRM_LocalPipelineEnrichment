# CLAUDE.md — ImperionCRM_LocalPipelineEnrichment

Guidance for Claude Code working on this repository. **Read this file fully before
making changes.** This is the **fourth repo** in the Imperion CRM system; it does not
stand alone. When a decision here conflicts with a quick instinct, this file wins unless
the human (Mark) says otherwise.

/handoff commits files to C:\Development\GitHub\handoff-memory\filename instead of system settings.

> **Four-repo system — read the siblings first.**
> - **`ImperionCRM`** (front end) — the **live** web app (`imperioncrm.azurewebsites.net`,
>   Entra SSO). **Owns the database schema and all migrations** (`db/migrations`, ADR-0017).
>   Authoritative UI. Surfaces client connection / GDAP relationship health. Token model:
>   per-connection secrets live in **Key Vault, never the database**.
> - **`ImperionCRM_Backend`** (Azure Functions) — *every process*: OAuth handshakes, real
>   outbound sends, credential storage, the orchestrator agent + sub-agents, semantic
>   search over the gold store. **AI stack settled there: Claude (generation) + Voyage
>   (embeddings)** — backend ADR-0034. Identity-gated: Easy Auth + caller allowlist,
>   public endpoint, no VNet (backend ADR-0035).
> - **`ImperionCRM_Pipeline`** (Azure Functions) — the *live-data plane* (pipeline
>   ADR-0011, 2026-06-09): **inbound webhook receivers** (Autotask tickets, Graph change
>   notifications), the **gdap-health** fail-closed sweep, the bronze→silver
>   **merge-sources** transform, and a caller-auth-gated **`POST /api/refresh`** for
>   targeted on-demand syncs. Its bulk-poll timers are RETIRED — this repo owns all
>   scheduled bulk ingestion — and it carries **no AI code at all**.
> - **`ImperionCRM_LocalPipelineEnrichment`** (this repo) — *on-prem, PowerShell,
>   scheduled-task ingestion + enrichment + vectorization engine*. Runs unattended on
>   Mark's home server, reads the full shared database locally, and does the **heavy,
>   high-volume work** that was choking the website: bulk source polling → bronze, the
>   bronze→silver→gold transforms, and **all embedding/vectorization**.
>
> **Schema is owned by the front-end repo.** This repo reads and writes the shared
> PostgreSQL + pgvector tables but **never owns migrations** — propose schema changes
> there and reference the new migration's ADR. Read the front-end
> `docs/database/data-model.md` ERD as the contract. **Do not invent tables here.**

---

## 1. What this repo is — and why it exists

The **on-prem data-pipeline engine** for Imperion CRM, written in **PowerShell** and run
as **Windows Scheduled Tasks** on Mark's home server. It exists to solve one problem:

> **Heavy data-pipeline processing was choking the website.** Bulk polling of every
> source, the bronze→silver→gold transforms, and (above all) embedding generation are
> high-volume, long-running, retry-heavy, and bursty. Running them inside the live web
> app or even the shared cloud App Service Plan starves interactive requests and the
> agent loop. So the bulk of the pipeline moves **off Azure compute** onto a machine Mark
> controls, where it can run on its own schedule against the full database with no
> per-second compute bill.

This repo writes into the **same shared PostgreSQL + pgvector database** the website
reads and the backend agent queries. It is a **producer of bronze/silver/gold rows and
vectors**, nothing else — it serves no UI and exposes no inbound network surface.

**The objective: capture _all_ the data the company knows — CRM *and* support — so the
front-end AI agents are aware of everything once these pipelines are running.** Leads,
accounts, contacts, proposals, and contracts (the CRM front) plus tickets, devices, and
the IT Glue / 365 operational picture (the support front) all land here, flow to gold,
and get embedded (§7) so the orchestrator agent can reason over the **complete** company
knowledge base. Coverage is the goal; gaps are bugs.

**Prefer many small jobs over one big job.** Mark is fine either way; the standard here is
**one scheduled task per (source, entity)** rather than a monolith — smaller jobs schedule
independently, retry in isolation, stay idempotent, give per-source observability and cost
telemetry, and let a slow or failing source never block the rest. Compose breadth from
many narrow, reliable tasks.

### The division of labour with the cloud `ImperionCRM_Pipeline`
The system now has **two pipeline planes** (decision: **coexist**, record as this repo's
first ADR):

| Work | Where it runs | Why |
| --- | --- | --- |
| **Inbound webhooks** — Autotask ticket webhooks; Graph change-notification subscriptions + renewal | **Cloud Pipeline** | A home server behind NAT/dynamic IP cannot reliably receive signed inbound webhooks. These must stay on a public, always-on HTTPS endpoint. |
| **Sub-minute, event-driven reactions** | **Cloud Pipeline** | Latency-sensitive; belongs next to the live app. |
| **Scheduled / bulk source polling → bronze** (all sources in §5) | **This repo (local)** | High volume, runs on a cadence, no public surface needed. |
| **bronze → silver → gold transforms** | **This repo (local)** | CPU-heavy, batchy, idempotent. |
| **Embedding / vectorization → pgvector** | **This repo (local)** | The heaviest, most bursty, most cost-sensitive stage — see §7. |

The boundary is a hard rule: **anything that must receive inbound internet traffic stays
in the cloud Pipeline; everything scheduled or compute-heavy runs here.** If a task seems
to require both, split it (cloud receiver writes a queue/landing row; local task picks it
up on its cadence).

---

## 2. Unattended execution — the certificate is the root of trust

These tasks run **with no human at the keyboard**. The entire unattended security model
hangs off **one certificate** on this machine. Treat that certificate as the crown jewel.

### The chain of trust
```
Scheduled Task (runs as a dedicated service identity, not Mark's user)
  └─ uses the machine Certificate (Cert:\LocalMachine\My, private key ACL'd to the task identity)
       ├─ (a) UNLOCKS the local PowerShell SecretStore
       │        via Unprotect-CmsMessage on a CMS blob encrypted to the cert  → vault password → Unlock-SecretStore
       └─ (b) IS the client credential for the Entra "enterprise app"
                via Get-MsalToken -ClientCertificate  → app-only token for Microsoft Graph / Azure ARM
```

### Rules
1. **Dedicated run-as identity.** Tasks run under a **gMSA** (preferred) or a dedicated,
   least-privileged local/domain service account — **never** Mark's interactive account.
   "Run whether user is logged on or not." Grant "Log on as a batch job."
2. **Certificate handling.** Cert lives in `Cert:\LocalMachine\My` with a
   **non-exportable** private key. Grant private-key read **only** to the task identity
   (`icacls` / `Set-Acl` on the key container). Nothing else on the box may read it.
3. **The SecretStore is opened by the certificate (literally).** Configure the vault
   `Set-SecretStoreConfiguration -Authentication Password -Interaction None`. Store the
   vault password as a **CMS message encrypted to the cert's public key**
   (`Protect-CmsMessage -To <thumbprint>`) on disk. At task start,
   `Unprotect-CmsMessage` (requires the cert private key) yields the password →
   `Unlock-SecretStore`. No password is ever in the repo, in a task argument, or in
   plaintext on disk. *(Fallback if CMS is impractical: `-Authentication None`, which
   binds the vault to the task identity via DPAPI — simpler, slightly weaker, document
   the choice in an ADR.)*
4. **What the SecretStore holds** (and the repo never does): the **embedding/LLM provider
   API keys** (§7) and each **source API key/secret** (Autotask, IT Glue, Apollo, KQM,
   DocuSign, website). It does **not** hold a Postgres password — DB access is a
   short-lived Entra token minted by the cert SP (§6). Cert-based app auth also means the
   Entra app needs **no client secret** in the vault — the cert is the credential. *(If a
   client secret is ever used instead of cert auth, it lives in the vault too; cert auth
   is preferred — confirm with Mark.)*
5. **No secrets in the repo, ever.** `.gitignore` must exclude any `*.cer/*.pfx`, exported
   secrets, and local config. Commit only `*.example` templates.
6. **Every task is idempotent and resumable** (§6) — an unattended retry must converge,
   never duplicate.

### Least privilege — the enterprise app's grant (agreed model)
The cert app is **read-only by default across all of Azure and Microsoft 365** — broad
*read*, **no write anywhere unless explicitly required**. The only write / data-plane
grants it holds are the three the pipeline genuinely needs:

| Grant | Role | Why |
| --- | --- | --- |
| **Azure Storage** | data-plane write | staging / landing for ingestion artifacts |
| **Shared PostgreSQL** | Postgres Entra role, table-scoped (§6) | write bronze/silver/gold + vectors |
| **Azure Key Vault** | `Key Vault Secrets User` | read the secrets / references it needs |

Everything else is **`Reader`** on the Azure plane and **read-only via GDAP** on 365 (§3).
**Any new write capability is an explicit, documented, human-approved grant (§8)** — never
added for convenience. (This replaces the earlier Owner-over-the-RG idea, which was far
broader than ingestion needs: a stolen home-server cert must not equal control of the prod
RG.) Record the as-built grant set in `docs/security/` and treat any widening as a
security event.

---

## 3. Client tenant access — GDAP, read-only (same model as the cloud Pipeline)

Imperion is operated by an MSP holding **GDAP (Granular Delegated Admin Privileges)
relationships with all clients.** GDAP is the **primary and preferred** path to client
M365 data — least-privileged, time-bound, per-customer, Zero-Trust by design. This repo
follows the cloud Pipeline's model exactly (see `ImperionCRM_Pipeline/CLAUDE.md §2`):

- The certificate-backed Entra app authenticates **in the partner (CSP) tenant** and
  reads each **customer tenant's Microsoft Graph through the delegated relationship**.
  No per-client app consent.
- **Least privilege via minimal GDAP roles** — request the fewest delegated roles that
  satisfy read needs; document the exact roles per source in `docs/integrations/`.
- **Relationships expire → fail closed.** A scheduled task monitors relationship state
  and surfaces expiring/expired relationships (to the front-end Integrations UI and to
  Mark). Expired access **stops that tenant's sync cleanly** — never silently retries.
- **Per-tenant isolation is absolute** — every ingested row is tagged with its owning
  customer tenant; **no cross-tenant reads** in any query path.
- **Fallback:** a client unreachable via GDAP → a read-only, admin-consented app
  registration for that one tenant, treated as the documented exception. GDAP first.

**Granting / widening / renewing GDAP roles is a security event** and a human-approval
gate (§8).

---

## 4. Tech stack & conventions (PowerShell)

- **PowerShell 7+ (pwsh)**, cross-edition-clean. No Windows PowerShell 5.1-only APIs.
- **Installed module, cmdlet-first (ADR-0007).** This ships as the versioned
  **`ImperionPipeline`** module (`src/ImperionPipeline/`, installed via
  `build/Install-ImperionModule.ps1`). Every operation is an **exported cmdlet** —
  `Invoke-Imperion*Sync` / `Export` / `Import`, plus `Set-ImperionPolicyGoldenState` /
  `Get-ImperionPolicyDrift`. **`Initialize-ImperionContext`** loads config + unlocks the
  SecretStore; machine config lives in `%ProgramData%\Imperion\` (outside the module).
  Scheduled tasks run `pwsh -Command "Import-Module ImperionPipeline;
  Initialize-ImperionContext; <cmdlet>"`. No loose entry scripts.
- **`Microsoft.PowerShell.SecretManagement` + `Microsoft.PowerShell.SecretStore`** for
  all secrets (§2). **`MSAL.PS`** for cert-based Entra tokens. **`Npgsql`** (.NET driver)
  or `psql` for Postgres (§6). Pin module versions in a manifest/`requirements.psd1`.
- **Comment-based help** (`.SYNOPSIS`/`.PARAMETER`/`.EXAMPLE`) on every public function.
  `[CmdletBinding()]`, typed params, `ShouldProcess` on anything that writes.
- **Human-readable, PSObject-first, flat tables.** Code reads like what it does — full,
  descriptive variable names that track the work (`$activeGdapRelationships`,
  `$flattenedDeviceRecords` — never `$x`, no terse aliases in committed code). Every source
  pull **flattens the source JSON into `[PSCustomObject]` rows holding only the attributes
  we actually care about** — a flat, table-shaped result (the shape you'd see in
  `Format-Table` or a CSV export). **Flat PSObject tables are the universal currency of
  this repo:** the same flattened table documents cleanly into IT Glue *and* imports into
  Postgres with no reshaping (§6).
- **Structured logging** — every run emits JSON log lines with run id, source, tenant,
  record counts, durations, and (for embeddings) token/cost (§7, §8). No `Write-Host` for
  data; use the logging helper. Logs are local files + optionally shipped to the same
  observability sink as the siblings.
- **Lint + test gates:** `PSScriptAnalyzer` (lint) and **Pester** (unit tests) must pass
  in CI before merge. Mirror the siblings' "lint + typecheck + build + test" gate.
- **No inline secrets, no plaintext creds, no `-AsPlainText` round-trips to disk.**

---

## 5. Data sources — the bronze catalog

**Bronze rule (applies to every source):** bronze **grabs every attribute the source API
exposes** — store the raw payload, lossless — **but present a filter** so silver can
refine later. We over-collect at bronze deliberately; we narrow at silver, never at the
API. Every bronze row carries: owning **tenant**, **source**, stable **external id**,
**content hash**, **collected_at**, and the **raw payload**.

Sources by entity (these are the *source* names; the **physical table names are defined
by the front-end migration**, see the note below):

| Entity | Bronze sources |
| --- | --- |
| **Companies** | `autotask_bronze` · `itglue_bronze` · `apollo_bronze` · `website_bronze` |
| **Users / Contacts** | `m365_contact_bronze` · `itglue_contact_bronze` · `autotask_contact_bronze` · `apollo_contact_bronze` · `website_contact_bronze` |
| **Devices** | `m365_devices_bronze` · `itglue_devices_bronze` · `website_devices_bronze` |
| **Proposals** | `kqm_proposal_bronze` · `website_proposal_bronze` |
| **Contracts** | `autotask_contract_bronze` · `docusign_contract_bronze` |
| **Tickets** | `autotask_ticket_bronze` |

**Security-posture sources (ADR-0008, read-only Graph/ARM):** in addition to the CRM/support
catalog above, the module ingests the Microsoft security estate:

| Area | What | Observed table(s) | Golden state |
| --- | --- | --- | --- |
| **Secure Score** | overall snapshots + control attributes | `secure_scores`, `secure_score_control_profiles` | — |
| **Conditional Access** | CA policies | `entra_conditional_access_policies` | `conditional_access_policies_golden` |
| **Intune security** | settings-catalog / endpoint security | `intune_security_policies` | `intune_security_policies_golden` |
| **Device configuration** | device config profiles | `device_configuration_policies` | `device_configuration_policies_golden` |
| **Autopilot** | deployment profiles | `autopilot_policies` | `autopilot_policies_golden` |
| **Defender XDR** | endpoint-security (AV/EDR/FW/ASR) | `defender_xdr_security_policies` | `defender_xdr_security_policies_golden` |

Each policy type keeps a **golden state** (approved baseline) so `Get-ImperionPolicyDrift`
can flag **compliant / drift / ungoverned / missing**; `Set-ImperionPolicyGoldenState`
promotes a current policy to baseline (human-gated). See §5-posture docs
(`docs/integrations/secure-score.md`, `security-posture-policies.md`,
`docs/database/golden-states-and-drift.md`).

Notes that bind to the existing system:
- **`website_*` is a first-class source.** Manual entries made in the web app are their
  own bronze source and carry the **highest merge precedence** (this matches the existing
  per-source bronze re-architecture: pipeline ADR-0009 / front-end ADR-0039, where manual
  `website_*` rows outrank machine sources and act as the resurrection guard).
- **`m365`, not `365`.** Digit-led source keys are prefixed `m` (existing convention).
- **Schema reconciliation is required before coding.** The existing physical bronze
  tables follow `{source}_companies` / `{source}_contacts` / `{source}_devices`
  (pipeline `shared/medallion.ts`). The names above use a `_bronze` suffix. **Pick one
  convention with the front-end repo and let its migration define the real tables** —
  do not create tables from PowerShell. Several of these sources are **new** to the
  schema (`kqm_proposal`, `docusign_contract`, `autotask_contract`, `autotask_ticket`,
  the `*_devices` set) and need front-end migrations first. Track this as an ADR + a
  cross-repo checklist.
- **Read-only sources, GDAP where applicable.** `m365_*` flows through GDAP (§3).
  Autotask / IT Glue / Apollo / KQM / DocuSign use their own API keys from the vault.

---

## 6. The canonical ingestion pattern & the write path

This is **how almost everything from Azure / 365 is collected**, and it's the same shape
end to end:

```
Source JSON (Graph / ARM / Autotask / IT Glue / Apollo / KQM / DocuSign / website)
   │  pull (scheduled, per source)
   ▼
FLATTEN          → [PSCustomObject] rows: only the attributes we care about, flat/table-shaped
   ├─────────────► DOCUMENT IN IT GLUE   (write the flattened records as IT Glue objects,
   │                                      and RELATE them to other IT Glue objects as needed —
   │                                      configs ↔ contacts ↔ organizations ↔ devices)
   ▼
BRONZE (Postgres)  the same flat table imports as-is — per (tenant, source, external_id) + hash
   │  normalize · dedupe · classify · map relationships · apply the bronze filter
   ▼
SILVER             unified contact / account / device / proposal / contract / ticket
   │  precedence merge (website > … machine sources)
   ▼
GOLD               summaries · knowledge objects (CRM + support, all entities)
   │  chunk · embed (§7)
   ▼
pgvector           embeddings the backend agent reads
```

**IT Glue is a first-class documentation + relationship hub, not just a source.** The
flattening step produces a flat PSObject table that serves two consumers from one shape:
1. it is **written into IT Glue** as documented objects, and **related to other IT Glue
   objects** (e.g. a device to its organization and primary contact) — this keeps the
   MSP's operational documentation current automatically; and
2. the **identical flat table imports straight into the Postgres bronze layer** with no
   reshaping.

Two notes that keep this inside the system posture:
- **Not every source flows through IT Glue.** The flatten→IT Glue→Postgres path is the
  norm for **operational / infrastructure data** (devices, configurations, the 365/Azure
  picture). Pure CRM/sales data (Apollo, KQM proposals, DocuSign contracts) flattens
  **straight to Postgres** — same flat-table shape, IT Glue step skipped where it adds
  nothing.
- **Writing to IT Glue is a write path.** Per the system posture (cloud Pipeline
  `CLAUDE.md §5`), IT Glue documentation writes stay **scoped and gated** — they document
  the MSP's own operational picture, never silently push beyond agreed scope. Surface a
  net-new IT Glue write surface for approval (§8).

- **Idempotency is mandatory.** Upsert on `(tenant, source, external_id)`; skip
  re-embedding when the content hash is unchanged (never re-bill an embedding for
  identical text). A re-run converges.
- **Writes target the physical per-source bronze tables; silver is recomputed by
  precedence** with manual `website_*` highest — same contract as the cloud Pipeline's
  `shared/merge.ts`. Read the union views (`*_bronze_all`); write the physical tables.
- **PostgreSQL access — short-lived Entra token, no stored DB password.** At task start
  the cert-backed Entra service principal mints a **short-lived AAD access token** for
  Azure PostgreSQL (`pgaadauth`); PowerShell connects with that token over **TLS
  (`sslmode=require`)**. The token is minted per run and **never persisted** — this
  matches the siblings' token-only posture (no long-lived DB secret anywhere). Needs: a
  **Postgres Entra role** for the SP with GRANTs scoped to **exactly the tables this repo
  touches**, and an Azure PostgreSQL **firewall rule for the home WAN IP**. **Operational
  gotcha:** a dynamic residential IP will break unattended runs — use a static IP, a VPN,
  or a small IP-refresh task, and document it in `docs/operations/`.
- **Never run schema migrations from here.** Schema changes are proposed in the front-end
  repo (ADR-0017). This repo fails loudly if an expected table/column is missing rather
  than creating it.

---

## 7. Vectorization — local orchestration, Voyage pinned (BUILT — ADR-0009)

This repo owns **all** embedding/vectorization (it moved off the website precisely
because it is the heaviest stage). The stack is **settled and built** (ADR-0009; system
decision 2026-06-09 — backend ADR-0034 / front-end ADR-0041):

- **Local orchestration.** Composing the gold corpus, chunking, dedup by content hash,
  batching to the provider's limits, retry/backoff, cost accounting, and the `pgvector`
  upsert **all run on this machine** (`Invoke-ImperionKnowledgeSync -Vectorize`, the
  `Imperion-KnowledgeVectorize` task). Large backfills never touch Azure compute.
- **Voyage `voyage-3-large` @ 1024, called directly.** No provider router — the system
  retired provider-agnosticism. The pinned constants (model, dimension, chunking `v1` =
  6000 chars / 500 overlap, batch size, cost rate) live in ONE place
  (`Get-ImperionVectorContract`); `Get-ImperionVoyageEmbedding` refuses any non-1024
  vector. The Voyage key is the SecretStore secret `embedding-provider-key`. The backend
  embeds only *queries* against the same contract. A local model (Ollama/ONNX) is a
  possible **future ADR** via a versioned re-embed — not dormant code.
- **Pin one model + dimension, system-wide.** Every vector row stores `embedding_model`,
  `dimension`, and `chunking_version`; a model/chunking change is a **versioned
  re-embed**, never an in-place overwrite — the vectorizer only ever touches rows
  matching its own version pair.
- **Chunking + lifecycle are documented** in
  [`docs/database/vector-lifecycle.md`](docs/database/vector-lifecycle.md) — the required
  artifact (§8 / front-end §8), updated as built.
- **Cost & idempotency telemetry on every run:** objects, chunks, billed tokens,
  estimated USD, provider/model/version, duration. Unchanged chunk-hash set → **no
  re-embed, no re-bill**.

---

## 8. Security posture ("Mythos Proof") & working agreement

Inherits the system-wide posture (front-end `CLAUDE.md §5`, §9) and the cloud Pipeline's
§7. Specifics for an unattended on-prem node:

- **No inbound network surface.** This repo receives nothing from the internet (that's the
  cloud Pipeline's job). It makes **outbound** calls only.
- **Certificate is the crown jewel** (§2). Compromise = vault + Entra app. Non-exportable
  key, ACL'd to the task identity, monitored. Plan cert rotation as a runbook.
- **Least privilege.** Read-only via minimal GDAP roles into 365; **read-only by default
  across Azure** (`Reader`), with write only to Storage / Postgres / Key Vault (§2). The
  Postgres role is scoped to exactly the tables this repo touches. New write = explicit,
  approved grant.
- **No secrets in repo or in plaintext on disk.** SecretStore only; CMS-protected unlock.
- **GDAP is time-bound — fail closed** (§3). Never operate against an expired relationship.
- **Audit + cost telemetry from day one** (§4, §7): every run, every external call, every
  embedding batch logged with counts, cost, and which tenant/GDAP relationship it used.
- **Idempotent + resumable** (§6): a failed/re-run task converges, never duplicates.
- **Human-approval gates (system-wide):** granting/widening/renewing GDAP roles, widening
  the Azure grant, touching billing, rotating the cert, or anything that could exfiltrate
  client data must surface for approval before running. Public-source enrichment
  (Apollo/website) stays inside the system's **lawful-basis + provenance** guardrail —
  every enriched field stamped `source` / `collected_at` / `lawful_basis`; having data is
  **never** consent to contact (see cloud Pipeline `CLAUDE.md §5`, front-end consent gate).

---

## 9. Documentation (REQUIRED — same standard as the siblings)

Code without docs is incomplete (front-end `CLAUDE.md §8`). Maintain in this repo a
`/docs` tree mirroring the system standard, and **write these ADRs first**:

1. **"Local PowerShell pipeline as the bulk-compute plane; cloud Pipeline keeps webhooks"**
   (the coexistence boundary, §1).
2. **"Certificate-rooted unattended execution + read-only-by-default grant"** — gMSA +
   cert + CMS-unlocked SecretStore (§2), and the agreed grant model (broad `Reader` +
   read-only GDAP; write only to Storage / Postgres / Key Vault).
3. **"Short-lived Entra token for Postgres (no stored DB password)"** — `pgaadauth` via
   the cert SP, table-scoped role, firewall/IP runbook (§6).
4. **"Vectorization: local orchestration with a pinned, pluggable embedding provider"**
   (§7).
5. **"Source bronze catalog + table-naming reconciliation with the front-end schema"**
   (§5) — and the new-source migration checklist.
6. **"IT Glue as a documentation + relationship hub in the ingestion path"** (§6) — the
   flatten→IT Glue→Postgres pattern, which sources use it, and the scoped/gated write
   posture.

Also maintain: `docs/integrations/` (one doc per source: auth, exact GDAP roles, rate
limits, cadence, fields, provenance, retry); `docs/operations/` (scheduled-task registry,
cert rotation runbook, Azure PG firewall/IP runbook, secret rotation); `docs/database/`
(cross-link the front-end ERD; document the bronze filter, medallion flow, and the vector
lifecycle); `docs/security/` (the cert trust chain + least-privilege posture).
Cross-reference sibling ADRs by **repo name** — ADR numbers are per-repo, not global.

---

## 10. Build order (suggested first tasks)

Confirm with Mark before wiring any scheduled task, requesting any GDAP role, or touching
the prod database.

1. **Scaffold** the PowerShell module + `scripts/` entry points + `tests/` (Pester) +
   `PSScriptAnalyzer` config + CI (lint/test + docs check). Add the `/docs` tree and the
   §9 ADR stubs.
2. **Unattended bootstrap** — register the gMSA/service account, install + ACL the cert,
   create the SecretStore, CMS-protect its password, and prove `Unlock-SecretStore` +
   `Get-MsalToken -ClientCertificate` work from a scheduled task with no human present.
3. **DB connectivity** — pull PG creds from the vault, connect over TLS, prove a scoped
   read/write against a throwaway test row. Sort the Azure PG firewall/IP story.
4. **GDAP token + relationship health** — partner-tenant auth, reach one customer tenant's
   Graph read-only, stand up the relationship-expiry surfacing task. Prove per-tenant
   isolation.
5. **First source end-to-end** — pick one (e.g. `autotask_bronze` companies): scheduled
   poll → bronze (full payload + filter) → silver upsert. Establish the idempotency +
   logging + cost-telemetry helpers everything else reuses.
6. **Fan out the remaining sources** (§5), reconciling table names with the front-end
   migration as you go.
7. **Silver → gold transforms** (summaries, knowledge objects).
8. **Vectorization stage** (§7) — chunk → embed → pgvector; verify the backend agent
   queries the vectors. Document the vector lifecycle.

Before each task, restate the plan briefly and flag anything conflicting with §2 (cert /
least privilege), §3 (GDAP), the schema-ownership rule (§5/§6), or the security posture
(§8).

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` at the repo root + ADRs in `docs/decision-records/`. See `docs/agents/domain.md`.
