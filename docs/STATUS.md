# Build status — ImperionCRM_LocalPipelineEnrichment

_Snapshot of where the `ImperionPipeline` module stands. Updated as layers land._

## Summary

- Module shipping at release **0.10.0**: **198 exported cmdlets**, ~199 hermetic Pester test
  files, **0 PSScriptAnalyzer findings** across `src/` + `build/`. The module imports clean on
  PowerShell 7.
- **Gold knowledge + vectorization LIVE in prod.** ~205 `knowledge_object` rows are composed
  from silver and **embedded with Voyage `voyage-3-large` @ 1024** by `Invoke-ImperionKnowledgeSync
  -Vectorize` (the nightly `Imperion-KnowledgeVectorize` task, 04:30). The Voyage key is
  provisioned (Key Vault `Voyage-Embedding-API-Key`, with the SecretStore mirror
  `embedding-provider-key`); the chunk-hash-idempotent vectorizer writes `knowledge_embedding`
  (front-end migration 0045 / ADR-0041). This is the system's sole embedding producer; the
  backend agent reads the vectors and embeds only queries against the same contract.
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

### Semantic-layer drift (front-end ADR-0086, #175)
- `Invoke-ImperionSemanticDriftSync` detects live-silver-vs-OKF-bundle drift (column **names
  only** — no data, no PII) and **proposes** a sync against the front-end bundle. Dry-run by
  default; never forks/edits the bundle; humans approve.

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

## Toolchain note

The module is `#Requires -Version 7.2` and tests use Pester 5. CI runs on `windows-latest`
(the on-prem Windows runtime). Machine-wide runtime deps (MSAL.PS, SecretManagement/SecretStore,
Npgsql) install via `build/Install-ImperionDependencies.ps1` before a live run; unit tests mock
them.

## Cross-repo note

The cloud `ImperionCRM_Pipeline` is limited to inbound webhooks + GUI-refresh polling; **all
bulk loads are owned by this repo**. The downstream **silver merge** (bronze → unified entities,
precedence) and the **OKF semantic-layer meaning** are front-end / cloud-Pipeline owned; this
repo proposes silver-shape / source-of-record / join changes back to the front-end OKF bundle at
merge (system `CLAUDE.md §11`). See [`cross-repo-action-items.md`](cross-repo-action-items.md).
