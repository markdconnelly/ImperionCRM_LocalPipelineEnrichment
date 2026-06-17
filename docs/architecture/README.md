# Architecture

_ImperionCRM_LocalPipelineEnrichment — `docs/architecture`_

System overview, the cloud/local boundary, and the diagrams for the on-prem pipeline plane.

- [`system-overview.md`](system-overview.md) — the cloud/local boundary (ADR-0001), the trust
  & data-flow summary, and the full **domain roster** (CRM/support, RMM/managed estate,
  security posture, finance/BI, logistics, scoped interaction, vectorization).
- [`go-live-roadmap.md`](go-live-roadmap.md) · [`production-readiness-plan.md`](production-readiness-plan.md)
  — what's gated and the path to live.

For the onboarding-grade narrative entry points, start with the repo
[`README.md`](../../README.md) (scheduled-task topology + medallion diagrams) and the
consolidated guides: [collector inventory](../collector-inventory.md),
[vectorization → gold](../vectorization-to-gold.md), [IT Glue hub](../it-glue-hub.md),
[security-posture bronze](../security-posture-bronze.md).

The master cross-repo map lives in the front end:
[`ImperionCRM/docs/architecture/system-of-systems.md`](../../../ImperionCRM/docs/architecture/system-of-systems.md).

> Part of the system-wide `/docs` standard. See [../../CLAUDE.md](../../CLAUDE.md).
