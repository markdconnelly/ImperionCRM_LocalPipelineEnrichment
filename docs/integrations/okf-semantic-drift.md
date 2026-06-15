# OKF semantic-layer drift agent

_ImperionCRM_LocalPipelineEnrichment — `docs/integrations`_

The on-prem enrichment agent that keeps the front-end **OKF semantic-layer bundle** in
sync with the live silver schema. It **detects drift** and **proposes** an update to the
bundle; a human approves and applies it in the front-end repo. Issue **#175**; standard
**front-end ADR-0086** (OKF semantic layer); ownership rationale: system `CLAUDE.md §11`.

> The bundle is owned by **`markdconnelly/ImperionCRM`** at
> `docs/database/semantic-layer/` (one concept file per silver entity + `coverage-matrix.md`
> + `index.md`). **This repo never forks the concept files and never edits the bundle
> directly.** It does the bronze→silver→gold shaping and ALL vectorization, so it "knows"
> the silver shape — which makes it the right home for staleness ownership (ADR-0086
> constraint 3). It proposes; the front end's canon stays single-homed.

## What "drift" means here

For each silver entity in `Get-ImperionSemanticCatalog`, the agent compares **column names
only** (no row data, ever) from the live relation to the columns documented in the matching
concept file's `## Schema` table, and classifies it:

| Status | Meaning |
|---|---|
| `in-sync` | documented columns exactly match the live relation |
| `drift` | both exist but the column sets differ (added / removed columns) |
| `missing-concept` | a live silver relation has **no** concept file yet (needs authoring) |
| `orphaned-concept` | a concept file exists but its live relation is gone / renamed |

The proposal lists, per concept: the file to touch (`tables/<concept>.md`), the columns to
**add** (live but undocumented) / **remove** (documented but gone), and a reminder to bump
the frontmatter `timestamp` and the `coverage-matrix.md` row.

## PII / boundary posture (load-bearing)

- **Column NAMES only cross the boundary.** Detection reads `information_schema.columns`
  (catalog metadata) — never a row, never a value. The OKF bundle is a PII-free meaning
  layer (ADR-0086; system `CLAUDE.md §8`/`§11`), so the agent must learn *shape* without
  touching *data*. Unlike OKF's reference enrichment agent (which walks BigQuery freely),
  this one is deliberately constrained.
- **No DDL, no client identifiers, no secrets** appear in a proposal — only column names
  and concept-file paths. The maintainer verifies meaning against the live read-only DB.
- **The agent never holds push rights to the front-end repo.** It proposes via an issue
  (today) or a reviewable PR (follow-up); humans merge.

## Execution model — dormant / fail-closed

| Mode | Trigger | Behaviour |
|---|---|---|
| **Dry-run** (default) | `Invoke-ImperionSemanticDriftSync` | detect + log drift; open **nothing** |
| **Execute → PR** | `-Execute` + token, drift carries column deltas | open a **cross-repo PR** on `markdconnelly/ImperionCRM` with the concept files already edited (issue #190) |
| **Execute → issue** | `-Execute` + token, drift is only `missing-concept`/`orphaned-concept` | file an **issue** (no file to edit — those need human authoring) |
| **Execute, no token** | `-Execute`, token unset | **fail-closed**: log a `Warn` and exit; never prompt, never store/print a token |
| **No bundle / no DB** | either | clean no-op (logged); never crashes the schedule |

### What the Execute → PR path does (issue #190)

On detecting `drift` rows (added/removed columns), the agent:

1. Clones `markdconnelly/ImperionCRM` to a temp dir using `$env:IMPERION_GH_TOKEN`
   (the token is scoped to **write a feature branch only**, never to merge), checks out
   `chore/okf-drift-<utc>`.
2. Edits each affected `tables/<concept>.md` `## Schema` table — **adds** a row per
   live-but-undocumented column (name backtick-wrapped, placeholder `_(?)_` type + a TODO
   pointing at the live read-only DB; the agent never invents a type), **removes** the row
   per documented-but-gone column — and bumps that file's frontmatter `timestamp`.
3. Bumps `coverage-matrix.md`'s frontmatter `timestamp` (system `CLAUDE.md §11` — the matrix
   rows are links, so the mechanical signal is the timestamp; the maintainer re-reviews the row).
4. Commits, pushes the branch, and opens a PR via `gh pr create`. **It never merges.** A
   maintainer applies the prose (definition / source-of-record / joins / PII) and merges.

Column **names** only ever cross the boundary; a name that is not a plain identifier is
rejected (no markdown/DDL injection). The token is handed to `git` only via an in-memory
remote URL and to `gh` via `$env:GH_TOKEN`, both scrubbed in `finally` — never on a CLI
argument, never on disk, never logged.

The scheduled task (`scheduled-tasks/semantic/drift-sync.task.ps1`) registers in **dry-run**.
Flip to live by setting `IMPERION_SEMANTIC_DRIFT_EXECUTE=1` and provisioning a
least-privileged `IMPERION_GH_TOKEN` — **only after Mark approves** auto-opening cross-repo
proposals.

## Bundle source

`Invoke-ImperionSemanticDriftSync` resolves a **local, read-only** copy of the bundle:
pass `-BundlePath <local checkout>/docs/database/semantic-layer`, or let it shallow-clone
`markdconnelly/ImperionCRM` to a temp dir (cleaned up after the run). It never writes to
that checkout.

## Cmdlets

| Cmdlet | Role |
|---|---|
| `Get-ImperionSemanticDrift -BundlePath <p>` | the detection core — returns one row per concept with status + column deltas |
| `Invoke-ImperionSemanticDriftSync [-BundlePath <p>] [-Execute]` | orchestrator + scheduled-task entry point |

Internal helpers (not exported): `Get-ImperionSemanticCatalog` (entity→relation→concept
map), `Get-ImperionSilverSchema` (column-name introspection), `Get-ImperionOkfConcept`
(concept-file parser), `New-ImperionSemanticDriftProposal` (proposal body + gated opener),
`New-ImperionSemanticDriftPullRequest` (clone→branch→edit→push→`gh pr create`),
`Edit-ImperionOkfConceptFile` (applies column-name deltas + timestamp to a concept file),
`Update-ImperionCoverageMatrixTimestamp` (bumps the matrix timestamp).

## Known limits / follow-up

- **The PR-opener is live (issue #190 shipped).** `-Execute` opens a cross-repo PR with the
  concept files already edited on a branch; it falls back to filing an **issue** only when the
  drift is purely `missing-concept`/`orphaned-concept` (nothing to edit mechanically — those
  need human authoring/reconciliation). The agent never merges.
- The agent proposes column-name deltas; it does **not** author the prose
  (definition / source-of-record / joins). It flags what to update and links ADR-0086;
  the maintainer writes the meaning. (A future enhancement could draft prose from the
  ERD — gated on never emitting PII.)
- The catalog mirrors the bundle's authored subset; expand both together as the bundle
  grows (front-end #536).

> Part of the system-wide `/docs` standard. See [../../CLAUDE.md](../../CLAUDE.md) and
> [the ADR](../decision-records/ADR-0016-okf-semantic-drift-agent.md).
