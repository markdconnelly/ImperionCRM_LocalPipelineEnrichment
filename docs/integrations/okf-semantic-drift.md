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
| **Execute** | `-Execute` **and** `$env:IMPERION_GH_TOKEN` set | open the proposal on `markdconnelly/ImperionCRM` |
| **Execute, no token** | `-Execute`, token unset | **fail-closed**: log a `Warn` and exit; never prompt, never store/print a token |
| **No bundle / no DB** | either | clean no-op (logged); never crashes the schedule |

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
(concept-file parser), `New-ImperionSemanticDriftProposal` (proposal body + gated opener).

## Known limits / follow-up

- The **PR-opening step is a documented stub**: `-Execute` files an **issue** on the
  front-end repo today. Opening a PR with the concept files already edited on a branch
  requires a clone+branch+push of `markdconnelly/ImperionCRM` and is deferred to **#190**.
- The agent proposes column-name deltas; it does **not** author the prose
  (definition / source-of-record / joins). It flags what to update and links ADR-0086;
  the maintainer writes the meaning. (A future enhancement could draft prose from the
  ERD — gated on never emitting PII.)
- The catalog mirrors the bundle's authored subset; expand both together as the bundle
  grows (front-end #536).

> Part of the system-wide `/docs` standard. See [../../CLAUDE.md](../../CLAUDE.md) and
> [the ADR](../decision-records/ADR-0016-okf-semantic-drift-agent.md).
