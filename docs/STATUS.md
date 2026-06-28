# Build status — ImperionCRM_LocalPipelineEnrichment

_Snapshot of where the `ImperionPipeline` module stands. Updated as layers land._

## Summary

- Module shipping at release **0.12.0**: **~190 exported cmdlets** (the lever-A surface-shrink,
  #226, has begun making internal helpers `Private`, narrowing the export list toward the ~30
  real entry points), ~200 hermetic Pester test files, **0 PSScriptAnalyzer findings** across
  `src/` + `build/`. The module imports clean on PowerShell 7.
- **This repo now owns the bronze→silver _merge_ for the sources it bulk-ingests** (ADR-0026,
  "merge co-locates with ingestion"): posture / Meta / DNS (the precedent) plus the new **M365
  directory groups** (`Invoke-ImperionM365DirectoryMerge`, #239) and **Azure ARM `cloud_asset`**
  (`Invoke-ImperionCloudAssetMerge`, #241), both wired into `Register-ImperionTask` (#243). The
  cloud Pipeline keeps only the live/webhook-driven merge and has ceded `cloud_asset` (Pipeline
  #135); the M365-directory cede (Pipeline #134) is **held** until the LP entra-group collectors
  fill `m365_groups` / `m365_group_members` bronze in prod.
- **Gold knowledge + vectorization LIVE in prod.** ~205 `knowledge_object` rows are composed
  from silver and **embedded with Voyage `voyage-3-large` @ 1024** by `Invoke-ImperionKnowledgeSync
  -Vectorize` (the nightly `Imperion-KnowledgeVectorize` task, 04:30). The Voyage key is the
  PLATFORM-scope AI credential read from Key Vault `conn-platform-voyage` (front-end ADR-0129 §8,
  folds #389 — the mis-named starter secret `Voyage-Embedding-API-Key` / SecretStore
  `embedding-provider-key` is retired); the chunk-hash-idempotent vectorizer writes
  `knowledge_embedding` (front-end migration 0045 / ADR-0041). This is the system's sole
  embedding producer; the backend agent reads the vectors and embeds only queries against the
  same contract.
- Built in the layered order from `CLAUDE.md §10` / `functions/README.md`:
  **connect → get → post → scheduled-task**. The full spine is built across ~25 source areas
  (CRM/support, security posture, finance/BI, logistics, scoped interaction). What remains is
  **operator/credential gating** — many newer collectors are built + tested but **DORMANT**
  until their API key, onboarding-app consent, or a front-end bronze migration lands.
- Every change shipped as its own branch → PR → merge (one PR per function/area). `main` on
  `origin` is the source of truth; nothing is local-only.

## Done

### Foundation
- Per-API restructure of `src/ImperionPipeline/Public/` into `<area>/{connect,get,post}` with a
  `utility/`, `posture/`, `security/`, `semantic/`, and `knowledge/` area; `functions/` is
  documentation mirroring the code areas.
- Shared scaffolds (one deep module, thin adapters): the post-writer scaffold
  `Invoke-ImperionBronzePost` (#105) and the knowledge-composer spine
  `Invoke-ImperionKnowledgeCompose` (#106). A new collector / composer adds a small adapter,
  never a copy of the scaffold.
- `build/Install-ImperionDependencies.ps1` (machine-wide runtime deps),
  `config/secret-names.example.psd1` reconciled to the real vault titles.
- `scheduled-tasks/` with a per-`(source, entity)` task file and a polling-cadence registry.

### Connect → get → post layers (per source)
Reusable auth + paged-request (`connect`), flatten-to-bronze-shape collectors (`get`), and
change-detected bronze writers (`post`) across the source roster. The full catalog —
source → connect → get → post → scheduled task → bronze target → cadence → ADR — is in
[`collector-inventory.md`](collector-inventory.md). Highlights:

- **CRM / support:** Autotask (company/contact/contract/ticket/time-entry), IT Glue
  (organization/contact/configuration + full export router), m365 (user/device + Teams/mail),
  KQM opportunities, DocuSign envelopes, Meta (FB/IG), Apollo, Plaud.
- **Security posture:** service principals, Azure + Sentinel inventory, Secure Score, the
  policy set + drift vs golden, Entra hygiene (domains / app-regs / role-assignments /
  groups / auth-methods), information protection (sensitivity labels, custom security
  attribute definitions), security incidents, Purview compliance, Dark Web ID, Telivy,
  EasyDMARC, DNS (zones / resolve / merge).
- **Finance / BI:** QuickBooks Online — invoices, payments, customers, estimates, bills,
  chart of accounts (full + expense-only), P&L snapshot, purchases; MileIQ business drives.
- **Logistics / procurement:** Amazon Business orders, CDW orders.
- **RMM / managed estate:** Datto RMM devices, Datto BCDR backups, myITprocess
  recommendations, UniFi devices.
- **Scoped interaction (ADR-0022):** allowlisted-principal ↔ client mail / Teams capture
  (message-grain, scoped at collection, count-only logging).

### Gold knowledge + vectorization (ADR-0009 — LIVE)
- Knowledge composers for **account, contact, contract, ticket, device, exposure,
  assessment, proposal, posture, social, and conversation_segment** entity types
  (`Get-ImperionKnowledge*` → `Set-ImperionKnowledgeObject`), all thin adapters over
  `Invoke-ImperionKnowledgeCompose`.
- Chunking v1 (`Split-ImperionTextChunk`), the Voyage client
  (`Get-ImperionVoyageEmbedding`, pinned `voyage-3-large` @ 1024, refuses other dimensions),
  and the vectorizer (`Invoke-ImperionVectorizeKnowledge`, chunk-hash idempotent, per-object
  replace, full cost telemetry). Entry point `Invoke-ImperionKnowledgeSync -Vectorize`.
- **Citation views** for conversation segments (`conversation_segment_citation`, front-end
  ADR-0068) trace a retrieved vector back to its source conversation + diarized turn.

### Bronze→silver merge (ADR-0026 — LP owns the merge for LP-ingested sources)
- `Invoke-ImperionPostureMerge` (classify `posture_policy` + roll up `tenant_posture`, ADR-0010
  — the precedent), `Invoke-ImperionDnsMerge` (golden/drift → `dns_domain`), the Meta merge
  (ADR-0013), and now **`Invoke-ImperionM365DirectoryMerge`** (Entra group membership →
  `contact_enrichment.directory_groups`, #239) + **`Invoke-ImperionCloudAssetMerge`** (`cloud_*`
  → silver `cloud_asset` CMDB CI, #241). Each is an idempotent, set-based, replace-from-source
  merge run by a `.task.ps1` immediately after its source's collectors (`Register-ImperionTask`
  ordering, #243).

### Azure ARM cloud-resource inventory + CMDB cloud-asset (ADR-0023, #217/#201)
- `Get-ImperionCloudResource` walks each consented tenant's subscriptions → resource groups →
  resources into `cloud_*` bronze (the estate fan-out from `account_tenant`, #234), merged into
  the silver `cloud_asset` entity — now a first-class CMDB configuration item with `cloud →
  account` edges + criticality (front-end #653, migration 0144 prod-applied). `cloud_*` tags
  emit as `jsonb` (42804 insert bug fixed, #237).

### Semantic-layer drift (front-end ADR-0086, #175/#249)
- `Invoke-ImperionSemanticDriftSync` detects live-silver-vs-OKF-bundle drift and **proposes** a
  sync against the front-end bundle. It now reconciles **the source-of-record / authority rule,
  not just column names** (#249) — no data, no PII. Dry-run by default; never forks/edits the
  bundle; humans approve. A cross-repo **okf-sync CI gate** (#245) requires a bronze-ingestion
  change to link an OKF concept update (front-end ADR-0104).

### Maturation refactors (architecture-deepening review, #225–#231)
- **One vendor secret resolver, not eight** — `Resolve-ImperionVendorSecret` + a catalog
  replaces eight near-identical `Get-Imperion<Vendor>Secret` clones (#228).
- **Vendored vector contract** — `Get-ImperionVectorContract` consumes the one canonical
  contract instead of a second hard-coded copy (ADR-0025 / #231), so the producer can never
  desync from the backend query side.
- **DPAPI unattended unlock** — SecretStore can unlock via `-Authentication None` (DPAPI-bound
  to the task identity) as a documented fallback where the cert lacks the Document Encryption
  EKU CMS needs (#223).
- **Module surface-shrink** — lever A privatized the knowledge-family internals (#226); lever D
  triaged the unscheduled surface *keep* (#227); the data-driven wrapper collapse #229 was
  deliberately **not** done (it would trade 23 debuggable components for one monolith).
- **Predictive lead score** — architecture recorded for a `kind='predicted'` ML lead score
  (ADR-0024 / #220), build pending.

### Quality pass
- Every public + private function has hermetic tests (mocking the network/secret/DB seams),
  except live-DB-only I/O. Real latent bugs fixed along the way (chiefly StrictMode
  missing-property throws across paging wrappers and posture syncs).

## Remaining (mostly operator/credential gating)

Built and tested, but **DORMANT** until the gate clears — each collector logs and exits cleanly
until then. See the per-source [`integrations/`](integrations/) doc and the registry for the
exact gate.

1. **Credential / consent gates (Mark):** QBO app registration (`qbo-access-token` /
   `qbo-realm-id`) for all finance collectors; onboarding-app consent + creds (#102) for
   security incidents / Purview / cross-org comms / scoped interaction; the RMM/managed-estate
   vendor keys (Datto RMM/BCDR, myITprocess); Amazon Business / CDW logistics keys; KQM /
   DocuSign / Dark Web ID / Telivy / EasyDMARC / UniFi / Plaud / MileIQ keys.
2. **Front-end bronze migrations** for the newest sources (Entra hygiene #260, information
   protection #259, UniFi, Plaud, Intune apps, EasyDMARC) — collectors gate on the table
   existing and fail loudly otherwise.
3. **Confirm-before-live field-shape checks** flagged in the integration docs (e.g.
   `m365_incidents.autotask_ticket_ref` format, Amazon/CDW cursor paging, Purview Graph
   surface) before the first live run of those paths.
4. **Composer breadth** — each further entity (IT Glue docs corpus, etc.) is one new composer
   + one line in `Invoke-ImperionKnowledgeSync`. Coverage is the goal, tracked in the
   production-readiness plan.
5. **M365-directory merge cede (Pipeline #134)** — the LP `Invoke-ImperionM365DirectoryMerge`
   is built + wired, but the cloud copy can only be ceded once the LP entra-group collectors
   actually fill `m365_groups` / `m365_group_members` bronze in prod (today empty → the merge
   has zero candidates and writes nothing). Verify the LP merge writes `contact_enrichment`
   in prod first, *then* cede.

## Toolchain note

The module is `#Requires -Version 7.2` and tests use Pester 5. CI runs on `windows-latest`
(the on-prem Windows runtime). Machine-wide runtime deps (MSAL.PS, SecretManagement/SecretStore,
Npgsql) install via `build/Install-ImperionDependencies.ps1` before a live run; unit tests mock
them.

## Cross-repo note

The cloud `ImperionCRM_Pipeline` is limited to inbound webhooks + GUI-refresh polling + the
**live/webhook-driven** silver merge; **all bulk loads — and the bulk bronze→silver merge for the
sources this repo ingests — are owned by this repo** (ADR-0026). The cloud keeps the
`website_*`-fed contact/account/device/contract/ticket/opportunity/expense sweep + DocuSign. The
**OKF semantic-layer meaning** of silver stays front-end-owned (ADR-0086); this repo proposes
silver-shape / source-of-record / join changes back to the front-end OKF bundle at merge (system
`CLAUDE.md §11`), and the okf-sync CI gate (#245) enforces it. See
[`cross-repo-action-items.md`](cross-repo-action-items.md).
