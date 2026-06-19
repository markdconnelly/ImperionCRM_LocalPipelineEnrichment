# OKF cross-repo sync gate (CI)

The `okf-sync` job in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)
implements the **LocalPipeline half** of the OKF freshness control — front-end
**ADR-0104** decision 6, layer 2 (cross-repo CI link-check). Tracking: this repo's
issue #245 / ImperionCRM #916.

## Why

This repo does the per-source **bronze ingestion** that feeds the silver tier. Adding,
removing, or re-shaping a source for a silver entity changes that entity's source set
— which the OKF concept file documents as part of its authority rule — often with **no
database migration**, so the front-end same-repo schema gate (#535) never fires. This
gate makes that change require a matching OKF concept update in ImperionCRM.

## What it does

On every pull request, the job diffs the PR against its base and flags changes to the
ingestion surface:

- `src/ImperionPipeline/Public/<source>/**` — per-source ingestion functions
- `Invoke-ImperionBronzePost.ps1` — the shared bronze writer

Excluded: the OKF/semantic tooling itself (`/semantic/`, `/knowledge/`, `/utility/`)
and `*.Tests.ps1`. If any flagged file changed, the PR must satisfy **one** of:

1. **Link an OKF update** — the PR body references an ImperionCRM issue/PR
   (`markdconnelly/ImperionCRM#NNN` or a full issue/PR URL) updating the matching
   concept file + `coverage-matrix.md`.
2. **Label `okf-sync`** — the OKF concept file was updated for this change.
3. **Label `okf-not-affected`** — escape hatch; change does not affect silver
   meaning. Justify in the PR body.

The concept files live in and are owned by ImperionCRM
(`docs/database/semantic-layer/`, ADR-0086 / §11); the fix is always a linked
ImperionCRM change.

## Layered defense

Layer 2 of three (ADR-0104 decision 6): layer 1 = ImperionCRM #535 gate; layer 3 =
this repo's reconciliation agent (#175) — the `New-ImperionSemanticDriftPullRequest` /
`Get-ImperionSilverSchema` machinery that diffs live behaviour vs the prose authority
rule and proposes drift PRs.
