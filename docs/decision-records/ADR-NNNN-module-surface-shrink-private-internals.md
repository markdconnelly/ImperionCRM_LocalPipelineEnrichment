# ADR-NNNN: ImperionPipeline module surface-shrink — Private internals, ~30 public entrypoints

<!-- PLACEHOLDER NUMBER. Claim the next free ADR number at merge (CLAUDE.md / system §10.3),
     rename this file, and fix the title + every reference. Do NOT reserve a number now. -->

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-19 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0007 (installed cmdlet-first module), ADR-0009 (vectorization stack) |

## Problem

`ImperionPipeline` exports ~200 commands through a hand-maintained `FunctionsToExport`.
The vast majority are **internal building blocks** — the per-entity `Get-Imperion*`
flatteners, the `Set-Imperion*ToBronze` write adapters, the per-API request clients, the
gold composers, the chunker, and the embedding client. Only ~9 commands are actually
scheduled and roughly ~30 are genuine entrypoints. Exporting everything bloats the public
surface, inflates the per-function test matrix (~190 test files), and turns the manifest
into a 200-line list that drifts. Module review (2026-06-18 handoff, epic #225) graded
this the highest-ROI, lowest-risk cleanup.

## Context

- **Cmdlet-first module (ADR-0007).** Every operation is a function in `src/ImperionPipeline/`,
  dot-sourced from `Private/` then `Public/` by the `.psm1`; `FunctionsToExport` in the
  `.psd1` is the **actual export gate**. A function not listed there is module-internal
  but still callable from inside the module — i.e. "Private" is a manifest + folder fact,
  not a language keyword.
- **Scheduled tasks compose entrypoints, not internals — mostly.** The CLAUDE.md §1
  "one scheduled task per (source, entity)" pattern means many `*.task.ps1` scripts call a
  `Get-Imperion*` / `Set-Imperion*ToBronze` pair **across the module boundary**. Those
  pairs must stay exported until their family grows an orchestrator. Therefore lever A is
  **not** a blanket privatization: a building block can only go Private if no out-of-module
  caller (task script, sibling repo) uses it — its only callers are in-module orchestrators.
- **Tests already test internals in-module.** The per-function Pester files overwhelmingly
  wrap their calls in `InModuleScope ImperionPipeline { … }`, which works whether the
  function is exported or Private. So privatizing a function does **not** require deleting
  or rewriting its test — at most it needs the existing direct calls wrapped in
  `InModuleScope` (kept as in-module Pester, per the issue).

## Options considered

1. **Lever A — make building blocks Private, keep only ~30 entrypoints public** *(chosen
   direction).* Per family: if the internals (`Get-*` composers, `Set-*` writer, chunker,
   embedding client) are reached **only** through that family's `Invoke-*Sync` orchestrator
   and no out-of-module caller, move them under `Private/` and drop them from
   `FunctionsToExport`. Behavior identical; internals stay callable in-module.
2. **Lever D — triage/prune the unscheduled source surface.** Complementary, separate
   sub-issue under #225 — out of scope here.
3. **Lever C — data-driven wrapper collapse.** Rejected in #225: high churn, low ROI,
   fights the human-readable PSObject-first convention (CLAUDE.md §4). Recorded here only
   as the not-taken path.

## Decision

Adopt **lever A** as the module's surface-shrink direction: the public surface is the set
of **genuine entrypoints** — the `Invoke-Imperion*Sync` orchestrators, the golden-state /
drift cmdlets, runtime setup (`Initialize-ImperionContext`, `Register-ImperionTask`), and
the intentionally-public reusable utilities — targeting ~30 exported cmdlets. Everything
else is a **Private building block**: it lives under `src/ImperionPipeline/Private/`, is
absent from `FunctionsToExport`, and is exercised in-module (`InModuleScope`) via its
public caller. **This is a visibility change only — never a logic change.**

Lever A lands **incrementally, one source family per micro-PR** (the families exceed the
~400-line micro-PR budget together). The first family is **`knowledge`** (gold composition
+ vectorization, ADR-0009): the 11 `Get-ImperionKnowledge*` composers, `Set-ImperionKnowledgeObject`,
`Split-ImperionTextChunk`, and `Get-ImperionVoyageEmbedding` become Private; only the two
orchestrators `Invoke-ImperionKnowledgeSync` and `Invoke-ImperionVectorizeKnowledge` stay
exported. Knowledge is the clean first cut because **no `*.task.ps1` script calls its
internals** — they are reached only through the two orchestrators. Remaining families
follow as sub-issues under #225.

**Eligibility rule for every future lever-A PR:** a function may go Private only if a
repo-wide search shows its sole callers are in-module (orchestrators / other internals) and
its own test — never a `scheduled-tasks/*.task.ps1` script or a sibling repo.

## Consequences

### Security impact

None. No grant, credential, network, or data-flow change — exported-symbol visibility only.
A smaller public surface is marginally better hygiene (fewer entry points to reason about).

### Cost impact

None at runtime. Lower maintenance cost: a tighter manifest and a test matrix that tests
internals through their callers instead of as standalone exported surface.

### Operational impact

Scheduled tasks are unaffected — they call the still-exported orchestrators (and, for
families not yet converted, the still-exported get/post pairs). `Import-Module` and every
scheduled `Invoke-*Sync` continue to resolve. Acceptance is the before/after
`Get-Command -Module ImperionPipeline` count plus an import smoke check.

## Future considerations

- Convert the remaining source families to lever A, one micro-PR each under #225, applying
  the eligibility rule above. Families whose tasks compose get/post pairs directly need an
  orchestrator first (overlaps lever B — pattern unification) before their internals can go
  Private.
- Lever D (prune unscheduled sources) and lever B (unify the two ingestion patterns) remain
  separate issues under #225.

## Cross-references

- Epic: issue #225 (module surface-shrink). This sub-issue: #226 (lever A).
- ADR-0007 — installed, cmdlet-first module (the export model this refines).
- ADR-0009 — settled embedding stack; the `knowledge` family converted first lives here.
- System CLAUDE.md §10.3 — ADR numbers claimed at merge (this file ships as `ADR-NNNN`).
