# Build status — ImperionCRM_LocalPipelineEnrichment

_Snapshot of where the `ImperionPipeline` module stands. Updated as layers land._

## Summary

- Module **v0.5.0**: **74 exported cmdlets**, **279 hermetic Pester tests**, **0
  PSScriptAnalyzer findings in `src/`**. Module imports clean on PowerShell 7.
- **Gold knowledge layer LIVE in prod (2026-06-09):** 205 `knowledge_object` rows
  (25 accounts · 83 contacts · 9 contracts · 88 tickets) written by
  `Invoke-ImperionKnowledgeSync` running interactively in `-SkipSecretStore` interim mode
  (markd-profile cert; KV reads via the SP's new `Key Vault Secrets User` grant; silver
  reads via front-end migration 0048). **Vectorization pending one operator step:** the
  Key Vault secret `Voyage-Embedding-API-Key` currently holds a placeholder — paste the
  real key and re-run `Invoke-ImperionKnowledgeSync -Vectorize`.
- Built in the layered order from `CLAUDE.md §10` / `functions/README.md`:
  **connect → get → post → scheduled-task**. Connect, get, the **post fan-out for every
  bronze table that exists today**, the **gold knowledge + vectorization stage
  (ADR-0009)**, and the **knowledge-composer fan-out (v0.5.0 — device, exposure,
  assessment, proposal, posture)** are complete; what remains is the Sentinel get, the
  posts whose bronze tables haven't landed yet (kqm/docusign/website), and the IT Glue
  docs composer.
- Every change shipped as its own branch → PR → merge (one PR per function). `main` on `origin`
  is the source of truth; nothing is local-only.

## Done

### Foundation
- Per-API restructure of `src/ImperionPipeline/Public/` into `<area>/{connect,get,post}` with a
  `utility/` and `posture/` area; `functions/` is documentation mirroring the code areas.
- README **data-model diagram** (medallion flow + the bronze→silver→gold/pgvector slice this repo
  produces), cross-linked to the front-end ERD (which owns the schema).
- `build/Install-ImperionDependencies.ps1` (machine-wide runtime deps), `config/secret-names.example.psd1`
  reconciled to the real vault titles (Autotask-API-*, ITGlue-API-Key, Telivy-API-Key, …).
- `scheduled-tasks/` with a polling-cadence registry.

### Connect layer (reusable auth + paged-request, per API)
- **m365** `Invoke-ImperionGraphRequest` · **azure** `Invoke-ImperionArmRequest` · **itglue**
  `Invoke-ImperionITGlueRequest` · **autotask** `Get-ImperionAutotaskZone` +
  `Invoke-ImperionAutotaskRequest` · **telivy** `Invoke-ImperionTelivyRequest` (x-api-key,
  links.next) · **darkwebid** `Invoke-ImperionDarkWebIdRequest` (bearer key).
- Private cores: `Invoke-ImperionHttp` (transport) + `Invoke-ImperionRestWithRetry` (429/503
  backoff), `Get-ImperionMember` / `Get-ImperionPropertyPath` (StrictMode-safe reads),
  `Test-ImperionCrossOrgComm` (m365 comms noise filter), `Get-ImperionAutotaskContext`,
  `ConvertTo-ImperionTagString`.

### Quality pass
- Every public + private function reviewed and given hermetic tests (mocking the network/secret/DB
  seams), **except** `Open-ImperionDbConnection` (live-DB I/O only). ~11 real latent bugs fixed —
  chiefly StrictMode missing-property throws across every paging wrapper and the posture syncs,
  plus an empty-rows bind defect, a module-state init bug, and a tag/object-count bug.

### Get layer (collect → flatten to bronze-shaped `[PSCustomObject]`; **no writes**)
| API | Collectors |
| --- | --- |
| **Autotask** | Company · Contact · Contract · Ticket |
| **m365** | User · Device · Mail · TeamsChat · TeamsMeeting *(Imperion↔client cross-org filter)* |
| **azure** | Subscription · ResourceGroup · Resource |
| **IT Glue** | Organization · Contact · Configuration (= devices) |
| **Telivy** | Report *(source `televy`)* |
| **Dark Web ID** | Compromise *(source `darkwebid`; key passed in — company credential)* |

### Security-posture sync cmdlets (end-to-end, pre-existing, hardened + tested)
`Invoke-ImperionServicePrincipalSync`, `…SecureScoreSync`, `…PolicySync` (+ drift),
`…AzureInventorySync`, `Get-ImperionPolicyDrift`, `Set-ImperionPolicyGoldenState`.

## Remaining

1. **azure Sentinel get** — the one deferred collector (per-workspace, multi-step: enumerate Log
   Analytics workspaces → analytic/automation rules, watchlists, workbooks).
2. **Post layer** — per-`(source, entity)` bronze writers. Take a get function's flat rows and
   `Invoke-ImperionBronzeUpsert` into the standard-envelope bronze tables; for **telivy/darkwebid**
   map to the ADR-0039 per-source shape (`external_ref` ← `external_id`, `payload_bronze` ←
   `raw_payload`) of `televy_reports` / `darkwebid_exposures`. Operational/infra sources also
   document into IT Glue (flatten → IT Glue → Postgres, ADR-0006).
   - **Done:** `Set-ImperionAutotaskContractToBronze` + `…TicketToBronze` (standard envelope) and
     `Set-ImperionTelivyReportToBronze` + `…DarkWebIdCompromiseToBronze` (ADR-0039 `external_ref`/
     `payload_bronze` remap via `Invoke-ImperionBronzeUpsert -NoChangeDetect`). All pipeline-accepting,
     open/reuse a short-lived-token connection, metric-log, `ShouldProcess`-gated; hermetic tests.
   - **Done (v0.4.0 fan-out, 9 writers):** ADR-0039-shape (migration 0036 tables, `external_ref`/
     `payload_bronze`, `-NoChangeDetect`): `Set-ImperionM365UserToBronze` → `m365_contacts`,
     `…M365DeviceToBronze` → `m365_devices`, `…ITGlueOrganizationToBronze` → `itglue_companies`,
     `…ITGlueContactToBronze` → `itglue_contacts`, `…ITGlueConfigurationToBronze` → `itglue_devices`.
     Standard envelope projected to the exact migration-0038 column sets (the collectors
     over-collect; extras stay in `raw_payload`): `Set-ImperionAzureSubscriptionToBronze`,
     `…AzureResourceGroupToBronze`, `…AzureResourceToBronze`. Multi-table router:
     `Invoke-ImperionITGlueExportToBronze` (export-envelope rows → `itglue_export_<entity>` by a
     per-row `entity` discriminator or `-Entity`, keyed `(source, external_id)`, unknown entity
     fails loudly). Same contract as the reference writers; hermetic tests for all nine.
   - **Still to fan out:** kqm/docusign/website posts once their sources are wired (their 0038
     tables exist; no collectors yet). Posture already writes via its `Invoke-*Sync` cmdlets.
3. **Scheduled-task files** — short `scheduled-tasks/<area>/*.task.ps1` composing get → post per the
   cadence registry, registered with `Register-ImperionTask`. Done: `autotask/contracts`,
   `autotask/tickets`, `telivy/assessments`, `darkwebid/compromises` (sources its API key from Key
   Vault via the new `Get-ImperionKeyVaultSecret`, the cert-SP reader for company credentials),
   `m365/users`, `m365/devices` (optional GDAP fan-out via `IMPERION_M365_TENANT_IDS`),
   `itglue/organizations`, `itglue/contacts`, `itglue/configurations`, `itglue/export`,
   `azure/inventory` (per-entity composition; Sentinel/mgmt-groups stay with
   `Invoke-ImperionAzureInventorySync` until the Sentinel get lands).
   **Note:** front-end migration 0044 grants the local-pipeline SP write on the 0038/0043 tables
   only — the migration-0036 tables the new writers target (`m365_contacts`, `m365_devices`,
   `itglue_companies`, `itglue_contacts`, `itglue_devices`) need a follow-up grant migration in
   the front-end repo before live runs.
4. ~~**Vectorization stage**~~ — **DONE (ADR-0009, v0.3.0).** Gold knowledge composers
   (`Get-ImperionKnowledgeAccount`/`Contact` → `Set-ImperionKnowledgeObject`), chunking v1
   (`Split-ImperionTextChunk`), the Voyage client (`Get-ImperionVoyageEmbedding`, pinned
   `voyage-3-large` @ 1024, refuses other dimensions), and the vectorizer
   (`Invoke-ImperionVectorizeKnowledge`, chunk-hash idempotent, per-object replace, full
   cost telemetry). Entry point `Invoke-ImperionKnowledgeSync -Vectorize`; scheduled as
   `Imperion-KnowledgeVectorize` (04:30). **To go live:** put the Voyage key in the
   SecretStore (`embedding-provider-key`) and run it once.
5. ~~**More knowledge composers**~~ — **DONE (v0.5.0)** for the mature entities:
   `Get-ImperionKnowledgeDevice` (silver `device` + not-yet-merged
   `itglue_export_configurations`, mirroring the front-end `device_inventory_all` view,
   migration 0053), `…CredentialExposure` (silver `credential_exposure`, facts only —
   no `payload_bronze`, no plaintext credentials in gold), `…AssessmentArtifact`
   (`assessment_artifact` + assessment/account context + `televy_reports` provenance),
   `…Proposal` (`proposal` + opportunity/account context), and `…Posture` (one object
   per tenant: latest Secure Score + per-type policy counts and named gaps via
   `Get-ImperionPolicyDrift`). All wired into `Invoke-ImperionKnowledgeSync`
   (entity types `device`/`exposure`/`assessment`/`proposal`/`posture`); `-Vectorize`
   picks the new objects up through the existing chunk/embed stage. Still to come:
   the IT Glue docs composer (once the doc corpus lands).
   **Note (read grants):** front-end migration 0048 granted the SP SELECT on
   `account`/`contact`/`opportunity`/`autotask_companies` only — the new composers also
   need SELECT on **`device`, `credential_exposure`, `assessment_artifact`,
   `assessment`, `proposal`, `itglue_devices`, and the `account_bronze_all` view** via
   a follow-up front-end grant migration before live runs (the posture/darkwebid/televy
   bronze reads are already covered by 0044's write grants).

## Toolchain note

The module is `#Requires -Version 7.2` and tests use Pester 5. PowerShell 7 + Pester 5 +
PSScriptAnalyzer were installed for development (the box originally had only Windows PowerShell
5.1 / Pester 3.4). The machine-wide runtime deps (MSAL.PS, SecretManagement/SecretStore, Npgsql)
are installed via `build/Install-ImperionDependencies.ps1` before a live run; unit tests mock them.

## Cross-repo note

The cloud `ImperionCRM_Pipeline` is limited to live polling for GUI refresh; **all bulk loads
(including Dark Web ID + Televy) are owned by this repo**. A task was filed there to scope its
darkwebid/televy poll timers down to GUI-refresh (front-end ADR-0040 added the destination tables).
