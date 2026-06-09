# Decision Records

_ImperionCRM_LocalPipelineEnrichment — `docs/decision-records`_

ADRs for every significant decision. **ADR numbers are per-repo** — always qualify a
cross-repo reference with the repo name ("backend ADR-0034", "front-end ADR-0041").

> Part of the system-wide `/docs` standard (front-end `CLAUDE.md` §8). See [../../CLAUDE.md](../../CLAUDE.md).

## Index

| ADR | Title | Status |
| --- | --- | --- |
| [0001](ADR-0001-local-bulk-plane-cloud-keeps-webhooks.md) | Local PowerShell bulk-compute plane; cloud Pipeline keeps webhooks | Accepted (completed by pipeline ADR-0011) |
| [0002](ADR-0002-certificate-rooted-unattended-execution.md) | Certificate-rooted unattended execution + read-only-by-default grant | Accepted |
| [0003](ADR-0003-short-lived-entra-token-postgres.md) | Short-lived Entra token for Postgres (no stored DB password) | Accepted |
| [0004](ADR-0004-vectorization-local-orchestration.md) | Vectorization: local orchestration, pinned pluggable provider | Accepted (amended by ADR-0009) |
| [0005](ADR-0005-source-catalog-and-table-naming.md) | Source bronze catalog + table-naming reconciliation | Proposed |
| [0006](ADR-0006-itglue-documentation-relationship-hub.md) | IT Glue as documentation + relationship hub | Accepted |
| [0007](ADR-0007-installed-powershell-module.md) | Installed PowerShell module (no loose scripts) | Accepted |
| [0008](ADR-0008-golden-states-and-drift.md) | Golden states + drift detection for security-posture policies | Accepted |
| [0009](ADR-0009-settled-embedding-stack-voyage-direct.md) | **The embedding stack is settled: Voyage direct, pinned, built** | Accepted |
