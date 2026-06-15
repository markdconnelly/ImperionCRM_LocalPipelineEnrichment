# ADR-0016: OKF semantic-layer drift agent (on-prem, propose-only)

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-14 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | frontend ADR-0086 (OKF semantic layer); frontend #535/#536; this repo #175/#176 |

<!-- ADR number is a placeholder (NNNN); claimed at MERGE per system CLAUDE.md §10.3. -->

## Problem

The front-end **OKF semantic-layer bundle** (`ImperionCRM/docs/database/semantic-layer/`,
frontend ADR-0086) curates the *meaning* of every silver entity — its shape, authoritative
source, and join paths. It is hand-maintained, so it **drifts** from the live silver schema
the moment a column is added or removed and nobody updates the concept file. ADR-0086
constraint 3 says staleness must be **owned by pipeline operations, not hand-maintenance**.
The interim guard is a front-end docs-gate CI check (#535); the durable "agent later" half
is this repo (#175).

## Context

- This repo does the bronze→silver→gold shaping and ALL vectorization, so it already
  "knows" the silver shape — the natural home for a drift detector (system `CLAUDE.md §1`).
- The bundle is owned by the front end (schema ownership, `§1`; one-canon rule, `§11`).
  A sibling must **propose**, never fork the concept files or edit the bundle directly.
- The OKF bundle is **PII-free by mandate** (ADR-0086; `CLAUDE.md §8`). Unlike OKF's
  reference enrichment agent (which walks BigQuery rows), this agent must learn *shape*
  without reading *data*.
- This is an unattended on-prem node with **no inbound surface** and a fail-closed posture
  (`§8`): a missing credential must log-and-exit, never prompt or crash a schedule.

## Options considered

1. **Hand-maintenance + CI gate only** — relies on authors remembering; the gate (#535)
   catches front-end PRs but not schema reality drifting underneath. Rejected as the sole
   mechanism (it is the interim guard, not the durable one).
2. **Auto-edit the bundle from this repo** — would fork/duplicate the canon, violating the
   one-home rule (`§11`). Rejected.
3. **On-prem detector that PROPOSES cross-repo updates** (chosen) — detect drift locally,
   open a human-reviewed proposal against the front-end repo; never merge, never fork.

## Decision

Ship a propose-only drift agent in the `ImperionPipeline` module:

- **Detection core** `Get-ImperionSemanticDrift` compares **column NAMES only**
  (`information_schema.columns`) to the columns documented in each concept file's
  `## Schema` table, classifying `in-sync` / `drift` / `missing-concept` /
  `orphaned-concept` with add/remove column deltas. No row, no value, no PII ever crosses
  the boundary.
- **Orchestrator** `Invoke-ImperionSemanticDriftSync` (scheduled-task entry point) resolves
  a read-only copy of the bundle, runs detection, logs a per-status summary, and hands
  non-`in-sync` drift to the proposal builder.
- **Propose-only, gated.** `New-ImperionSemanticDriftProposal` builds a PII-free,
  column-name-only proposal body. **Dry-run by default** (opens nothing). `-Execute`
  opens a proposal on `markdconnelly/ImperionCRM` and is **fail-closed**: it requires
  `$env:IMPERION_GH_TOKEN` or logs a `Warn` and exits, never prompting or printing a token.
- **PR-opener (issue #190, shipped).** When `-Execute` + token find drift carrying column
  deltas, `New-ImperionSemanticDriftPullRequest` clones the front-end repo to a temp dir,
  branches `chore/okf-drift-<utc>`, edits each affected concept file's `## Schema` table
  (`Edit-ImperionOkfConceptFile` — column NAMES only, placeholder type, no DDL) and its
  frontmatter `timestamp`, bumps `coverage-matrix.md`'s timestamp
  (`Update-ImperionCoverageMatrixTimestamp`, system `CLAUDE.md §11`), commits, pushes, and
  opens a PR via `gh pr create`. **The agent never merges.** When the drift is purely
  `missing-concept`/`orphaned-concept` (no mechanical edit to make) it falls back to filing
  an **issue**, so author-required drift is still surfaced.

## Consequences

### Security impact

Read-only against the DB (catalog metadata only). Against the front-end repo the agent now
writes a **feature branch and opens a PR** — but it holds **no merge rights** and the
write token is least-privileged + Mark-gated + behind `IMPERION_SEMANTIC_DRIFT_EXECUTE`;
absent the token the live path is fail-closed. No secret is stored, logged, or passed on a
command line — the token is read from an env var by reference, handed to `git` only via an
in-memory remote URL and to `gh` via `$env:GH_TOKEN`, both scrubbed in `finally`. The PII
boundary is enforced structurally: only column **names** leave the function, and a name
that is not a plain identifier is rejected (no markdown/DDL injection).

### Cost impact

Negligible — one metadata query per silver relation on a weekly cadence; no embedding,
no LLM calls.

### Operational impact

A new weekly scheduled task (`scheduled-tasks/semantic/drift-sync.task.ps1`), registered in
dry-run. Live auto-opening is opt-in (`IMPERION_SEMANTIC_DRIFT_EXECUTE` + a least-privileged
token), Mark-gated. A cold node with no bundle / no token / no DB does a clean no-op.

## Future considerations

- ~~Promote the issue-filing stub to a real cross-repo **PR**~~ — **done** (issue #190).
- Draft concept *prose* (definition / source / joins) from the ERD, gated on never emitting
  PII (today the agent proposes column deltas only).
- More valuable once the bundle expands past the pilot subset (front-end #536); keep the
  catalog in step. Vectorizing the bundle into gold is #176.

## Cross-references

frontend ADR-0086 (the OKF semantic-layer standard); frontend #535 (interim docs-gate),
#536 (bundle expansion); this repo #175 (this agent), #176 (bundle vectorization).
System `CLAUDE.md §11` (OKF canon) / `§8` (read-only DB + PII). Integration doc:
`docs/integrations/okf-semantic-drift.md`.
