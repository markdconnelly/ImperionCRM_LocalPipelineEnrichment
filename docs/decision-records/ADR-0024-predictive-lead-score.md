# ADR-0024: Predictive (ML) lead score — an LP scheduled pass writing `lead_score (kind='predicted')`

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-17 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | frontend ADR-0073; frontend ADR-0042; frontend ADR-0041; frontend migration 0116; backend #138; frontend #319 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as `ADR-0024`; renumber to
> the next free local-pipeline ADR number at merge if it collides, fixing every reference. Do
> not reserve a number now.

> **Scope.** This ADR decides the **model architecture** for the `predicted` half of the
> lead-score contract and records **why it lives in this repo**. It does **not** change the
> `lead_score` table or its contract — that contract is already decided in **frontend ADR-0073
> decision 5** (marketing-automation-journeys), and the physical table already exists in prod
> (**frontend migration 0116**). The **rule** slice already shipped (frontend #401, closed);
> this ADR is about the **predicted** slice only. No DDL is defined here (schema is
> front-end-owned, system §1).

## Problem

The `lead_score` contract (frontend ADR-0073 d5, table from frontend migration 0116) defines
**two coexisting score kinds** per contact — `rule` and `predicted` — each one current row
under UNIQUE `(contact_id, kind)`. The **rule** kind shipped: a transparent, hand-weighted
score the app can band today. But the rule score by construction only captures the patterns a
human thought to encode; it **misses the non-obvious combinations** of engagement and fit that
actually predict conversion. The `predicted` half of the contract is defined but **unbacked** —
no process computes it, so the column is permanently empty and the contract is half-delivered.

What forced the decision: deciding **what computes `predicted`, where it runs, and how it stays
honest** — without re-opening the table contract and without letting an ML/bulk workload land
in the wrong repo.

## Context

- **The output contract is already fixed (frontend ADR-0073 d5, migration 0116).** `lead_score`:
  `kind ∈ {rule, predicted}`, `score numeric` banded 0..100, `breakdown jsonb` (explainable
  per-feature contributions), `computed_at`; UNIQUE `(contact_id, kind)`. Re-scoring is an
  **idempotent UPSERT** on `(contact_id, kind)` — exactly one current row per (contact, kind).
  The two kinds **coexist**; `predicted` never overwrites `rule`. This ADR consumes that shape;
  it does not alter it.
- **Four-repo doctrine (system §1, frontend ADR-0042).** This repo (local-pipeline) owns **ALL
  ML / vectorization and heavy bulk compute**. The front end is GUI-only and **owns the schema**.
  The backend owns the **agent / process runtime**. "Processes run outside the GUI" (frontend
  ADR-0042) puts the scoring *pass* here; the FE only **reads** `lead_score` to render bands.
- **Schema is front-end-owned (system §1).** The table exists (migration 0116); this repo is a
  **writer only** of `lead_score (kind='predicted')` and **fails loudly** if the table is absent
  (the standing fail-loud-on-missing-table posture, ADR-0005). No DDL here.
- **Inputs already exist in silver.** Engagement / interaction history (interactions, email
  opens / clicks / replies, recency / frequency cadence) plus fit attributes are already merged
  to silver by existing collectors and the silver merge. The predicted pass is a **reader** of
  silver — it introduces **no new ingestion source** and **no new PII surface**.
- **Embedding stack is settled (ADR-0009, frontend ADR-0041).** Voyage `voyage-3-large` @ 1024
  is the one pinned vector space; any embedding-derived feature reuses it (no second provider).
- **Parent epics:** backend #138 / frontend #319 (marketing-automation processes). This is the
  local-pipeline slice of that program.

## Options considered

1. **Rule-only (status quo).** Keep only the hand-weighted `rule` score; leave `predicted`
   permanently empty. *Rejected* — the rule score misses non-obvious engagement/fit patterns,
   and the contract (ADR-0073 d5) explicitly provisioned `predicted` as the complement. Leaving
   it empty half-delivers the contract.
2. **Predicted score computed in the backend agent runtime.** Run the model inside the backend's
   orchestrator/process runtime. *Rejected* — ML and heavy bulk compute belong in **this repo**
   by doctrine (system §1, frontend ADR-0042); the backend owns the **agent** runtime, not bulk
   model training/scoring. Putting a training + bulk-scoring workload there violates the repo
   split and duplicates the embedding/ML stack that already lives here.
3. **Predicted score as an LP scheduled pass (chosen).** A scheduled local-pipeline pass reads a
   contact's silver engagement/interaction history, runs the predictive model, and writes
   `lead_score (kind='predicted')` with an explainable `breakdown` — the same scheduled-pass
   shape as the existing posture-merge / snapshot passes (ADR-0010 / ADR-0011). *Chosen* — keeps
   ML/bulk in the repo that owns it, reuses the proven scheduled-pass + idempotent-upsert
   machinery, and coexists with the rule score without touching it.

## Decision

**Add a predictive (ML) lead score as a local-pipeline scheduled pass.** The pass reads a
contact's engagement / interaction history from silver, produces a model score banded **0..100**
with an explainable per-feature **`breakdown`**, and writes it to **`lead_score (kind='predicted')`**
via an **idempotent UPSERT** on `(contact_id, kind)`. It **coexists with — never replaces —** the
`rule` score; the application chooses/bands between the two.

### 1. Inputs (feature families, not a final list)

The model reads only signals already in silver. Named at the **family** altitude (the concrete
feature list is a model-build decision, not an architecture decision):

- **Engagement signals** — email opens / clicks / replies, message-grain interactions
  (interactions timeline).
- **Recency / frequency / cadence** — how recently and how often a contact engages, trend over
  time.
- **Fit attributes** — account / contact attributes already enriched onto silver (industry,
  size, role-shape, etc.).
- **(Optional, later) embedding-derived similarity** — similarity over the settled Voyage @ 1024
  gold space (ADR-0009 / frontend ADR-0041) to known-converting profiles. Reuses the one pinned
  vector contract; no new provider.

No new ingestion source, no new PII surface — the pass is a **reader** of existing silver.

### 2. Output contract (unchanged — frontend ADR-0073 d5 / migration 0116)

- Writes `lead_score`: `kind='predicted'`, `score` banded **0..100**, `breakdown jsonb` (explainable
  per-feature contributions, **mirroring the rule score's breakdown shape**), `computed_at`.
- **Idempotent UPSERT** on UNIQUE `(contact_id, kind)` — one current `predicted` row per contact,
  re-scored in place on each pass.
- **Never touches the `rule` row.** The two kinds coexist; the app bands/chooses between them.
  No silent replacement of the rule score, ever.

### 3. Coexistence + honesty (degrade-to-rule)

Until the predicted model is **trained and live**, the system **degrades to rule-only**: the
`predicted` row is simply **absent**, and the app falls back to the rule band. There is **no
placeholder, no zero-filled, no silently-substituted** predicted row. When the model goes live,
the pass starts populating `predicted`; the rule row is untouched throughout. Honesty over
coverage: an absent predicted score reads as "not yet modelled," never as a low score.

### 4. Explainability (required — mirrors frontend ADR-0073 d5)

The `breakdown` jsonb is **mandatory**, not optional. The pass surfaces **per-feature
contributions** (which signals pushed the score up/down and by how much), mirroring the rule
score's explainable breakdown — so the front end renders *why* a contact scored as it did, not a
black-box number. A model whose contributions cannot be surfaced does not satisfy this contract.

### 5. Quality gate / evaluation (gating precondition)

The pass writes `predicted` rows **only after** the model clears a quality gate:

- **Sufficient training history** — enough labelled engagement history (engagement → known
  outcome) to fit a model that generalizes; below that threshold the pass stays dormant
  (degrade-to-rule, §3).
- **Offline evaluation** — an offline eval (held-out performance + calibration of the 0..100
  band) passes before the model is promoted to writing live.

Until both clear, the pass is **dormant** (no `predicted` rows) — the honest degrade-to-rule
state. This gate is the precondition for go-live, flagged here as the controlling dependency.

### 6. Where it runs / cadence

A **local-pipeline scheduled pass** — the same shape and machinery as the existing scheduled
silver passes (`Invoke-ImperionPostureMerge`, ADR-0010; `Invoke-ImperionPostureSnapshot`,
ADR-0011): one scheduled task, idempotent per run, run-as the local service account (ADR-0012).
Initial cadence and **model retraining cadence** are operational tuning, recorded under Future
considerations — the architecture fixes the *pattern* (scheduled LP pass), not the exact clock.

## Consequences

### Security impact

- **No new PII surface.** The pass **reads existing silver** only — no new ingestion source, no
  new credential, no new external call beyond the already-settled Voyage path (ADR-0009) if/when
  embedding features are used. **Never commit secrets** (system §2) — none are introduced.
- **Lawful basis already carried.** The silver facts the model reads already carry `lawful_basis`
  / provenance on enriched facts (the front-end invariant); the score is a derived aggregate of
  consented/lawful silver, introducing no new basis question. The score itself is operational
  derived data, not a new personal-data category.
- **No write surface beyond `lead_score (kind='predicted')`.** The pass writes exactly that one
  kind, idempotently; it never writes the `rule` row, never writes outside the table.

### Cost impact

- **Qualified / honest.** If the model is a **lightweight tabular model** over silver features,
  per-run scoring cost is negligible (CPU-bound bulk pass, no per-contact LLM call). If
  embedding-derived similarity features are used, they reuse the **already-incurred** Voyage @
  1024 vectors (chunk-hash idempotency means unchanged content is never re-billed, ADR-0009) —
  query-time similarity over existing vectors, not new embedding spend. **Training** cost is
  bounded and infrequent (periodic retrain, not per-run). No new standing cost line is asserted
  here beyond the existing embedding budget; the exact model choice is deferred (Future
  considerations).

### Operational impact

- **Training-data dependency is the gating risk.** The pass cannot go live until §5 clears
  (sufficient labelled history + a passing offline eval). Until then it is **dormant**;
  degrade-to-rule (§3) is the steady operating state, and that is the honest default, not a
  failure.
- **Retraining loop.** A periodic retrain + re-eval cadence must be established before live
  operation and maintained after (model drift as engagement patterns shift). Cadence is Future
  considerations.
- **One scheduled task**, registered at server bringup (the standing scheduled-task-registry
  pattern, ADR-0012), idempotent and re-runnable; a failed run leaves the prior `predicted` rows
  intact (UPSERT, no destructive delete).
- **Front-end is read-only on this** — it bands/chooses; no FE change is required to *land* the
  contract (the column already exists, migration 0116). A later silver/OKF note (system §11) is
  filed in the front end only if the predicted score becomes a documented silver entity surface.

## Future considerations

- **Concrete model choice + feature list.** Tabular gradient-boosted model vs. embedding-assisted
  vs. hybrid — a model-build decision, made once enough labelled history exists (§5). This ADR
  fixes the *pattern* and *contract*, not the algorithm.
- **Retraining cadence + drift monitoring.** How often to retrain, what drift signal triggers an
  off-cadence retrain, and how the offline eval is re-run on each retrain.
- **Scoring cadence tuning.** Initial scheduled cadence and whether event-driven re-scoring (on a
  burst of new engagement) is worth adding later.
- **Calibration of the 0..100 band.** Keeping the predicted band semantically comparable to the
  rule band so the app can present them coherently.
- **Embedding-derived features.** Whether similarity-to-converters over the Voyage @ 1024 space
  (ADR-0009) measurably improves the model enough to justify wiring it in.

## Cross-references

frontend ADR-0073 (marketing-automation-journeys — **decision 5** fixes the `lead_score` two-kind
contract + explainability; this ADR backs its `predicted` half) · frontend ADR-0042 (processes run
outside the GUI — why the scoring pass lives in this repo, not the front end) · frontend ADR-0041
(the pinned Voyage @ 1024 vector contract, mirrored here by ADR-0009) · frontend migration 0116
(the physical `lead_score` table this pass writes) · ADR-0009 (settled embedding stack — reused for
any embedding-derived feature) · ADR-0010 / ADR-0011 (the existing scheduled-pass machinery this
pass mirrors) · ADR-0012 (local service-account run-as identity) · ADR-0005 (fail-loud on missing
table). Issues: **#220** (this child — predictive lead-score ADR), **backend #138** / **frontend
#319** (parent epics — marketing-automation processes), **frontend #401** (the rule slice, closed).
