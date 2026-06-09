# Build status — ImperionCRM_LocalPipelineEnrichment

_Snapshot of where the `ImperionPipeline` module stands. Updated as layers land._

## Summary

- **46 exported cmdlets**, **175 hermetic Pester tests** across 51 files, **0 PSScriptAnalyzer
  findings**. Module imports clean on PowerShell 7.
- Built in the layered order from `CLAUDE.md §10` / `functions/README.md`:
  **connect → get → post → scheduled-task**. Connect and get are complete; post and the
  scheduled-task files are next.
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
3. **Scheduled-task files** — short `scheduled-tasks/<area>/*.task.ps1` composing get → post per the
   cadence registry, registered with `Register-ImperionTask`.
4. **Vectorization stage** (`CLAUDE.md §7`) — chunk → embed → pgvector, after gold exists.

## Toolchain note

The module is `#Requires -Version 7.2` and tests use Pester 5. PowerShell 7 + Pester 5 +
PSScriptAnalyzer were installed for development (the box originally had only Windows PowerShell
5.1 / Pester 3.4). The machine-wide runtime deps (MSAL.PS, SecretManagement/SecretStore, Npgsql)
are installed via `build/Install-ImperionDependencies.ps1` before a live run; unit tests mock them.

## Cross-repo note

The cloud `ImperionCRM_Pipeline` is limited to live polling for GUI refresh; **all bulk loads
(including Dark Web ID + Televy) are owned by this repo**. A task was filed there to scope its
darkwebid/televy poll timers down to GUI-refresh (front-end ADR-0040 added the destination tables).
