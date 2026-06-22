# Architecture

_ImperionCRM_LocalPipelineEnrichment — `docs/architecture`_

System overview, the cloud/local boundary, and the diagrams for the on-prem pipeline plane.

- [`system-overview.md`](system-overview.md) — the cloud/local boundary (ADR-0001), the trust
  & data-flow summary, and the full **domain roster** (CRM/support, RMM/managed estate,
  security posture, finance/BI, logistics, scoped interaction, vectorization).
- [`go-live-roadmap.md`](go-live-roadmap.md) · [`production-readiness-plan.md`](production-readiness-plan.md)
  — what's gated and the path to live.

### Deep dives — how the memory is built (rabbit-hole depth)

This repo physically realizes the system's memory (it does ALL vectorization, gold
summarization, and consolidation — the "hippocampus", `CLAUDE.md §1`). The two memory deep
dives explain the data-structure decisions and are linked directly from the front-end
executive summary:

- [`deep-dives/mempalace-memory-architecture.md`](deep-dives/mempalace-memory-architecture.md)
  — borrowing MemPalace's memory-palace pattern (not a dependency), realized on Postgres +
  pgvector: gold `knowledge_object` + the pinned Voyage 1024 vector space, the gold hybrid
  ranker (FE ADR-0115), two-level recall (gold summary → verbatim bronze, FE ADR-0113).
- [`deep-dives/open-brain-second-brain.md`](deep-dives/open-brain-second-brain.md)
  — borrowing OpenBrain/OB1's second-brain structure for the tiered knowledge memory
  (canon · company · personal — 6 personal brains), the Personal Knowledge Store (FE
  ADR-0114), and the Universal Memory MCP (FE ADR-0116).

Both link UP to the front-end canonical synthesis
[`how-it-all-fits-together.md`](https://github.com/markdconnelly/ImperionCRM/blob/main/docs/architecture/deep-dives/how-it-all-fits-together.md)
and the public papers
([executive summary](https://github.com/markdconnelly/ImperionCRM/blob/main/public/papers/executive-summary.html) ·
[research paper](https://github.com/markdconnelly/ImperionCRM/blob/main/public/papers/research-paper.html)).

For the onboarding-grade narrative entry points, start with the repo
[`README.md`](../../README.md) (scheduled-task topology + medallion diagrams) and the
consolidated guides: [collector inventory](../collector-inventory.md),
[vectorization → gold](../vectorization-to-gold.md), [IT Glue hub](../it-glue-hub.md),
[security-posture bronze](../security-posture-bronze.md).

The master cross-repo map lives in the front end:
[`ImperionCRM/docs/architecture/system-of-systems.md`](../../../ImperionCRM/docs/architecture/system-of-systems.md).

> Part of the system-wide `/docs` standard. See [../../CLAUDE.md](../../CLAUDE.md).
