# Documentation — ImperionCRM_LocalPipelineEnrichment

The on-prem PowerShell pipeline plane. Documentation is a **required deliverable and a
security control** — code without docs is incomplete (front-end `CLAUDE.md §8`). This tree
mirrors the system-wide standard.

## Start here
1. [`../CLAUDE.md`](../CLAUDE.md) — the working brief (boundary, cert trust chain, GDAP, sources, vectorization, build order).
2. [`../README.md`](../README.md) — the elevator version.
3. [`decision-records/`](decision-records/) — the ADRs below.

## Map of this tree

| Area | What lives here |
| --- | --- |
| [architecture/](architecture/) | System overview + the cloud/local boundary + diagrams. |
| [security/](security/) | [Certificate trust chain](security/certificate-trust-chain.md) · [least-privilege grants](security/least-privilege-grants.md). |
| [integrations/](integrations/) | One doc per source — [Entra SPs](integrations/entra-service-principals.md) · [Azure + Sentinel inventory](integrations/azure-resource-inventory-and-sentinel.md) · [Secure Score](integrations/secure-score.md) · [security-posture policies](integrations/security-posture-policies.md) · [IT Glue](integrations/itglue.md) · [Kaseya quotes/proposals](integrations/kaseya-quotes-proposals.md). |
| [database/](database/) | [Medallion + write path](database/medallion-and-write-path.md) · [IT Glue→Postgres relationships](database/itglue-to-postgres-relationships.md) · [golden states & drift](database/golden-states-and-drift.md) · [vector lifecycle](database/vector-lifecycle.md) · **[front-end schema handoff](database/front-end-schema-handoff.md)**. |
| [operations/](operations/) | [Scheduled-task registry](operations/scheduled-task-registry.md) · [change detection](operations/change-detection.md) · [cert rotation](operations/certificate-rotation.md) · [secret rotation](operations/secret-rotation.md) · [Azure PG firewall/IP](operations/azure-postgres-firewall.md). |
| [data-governance/](data-governance/) | Provenance + lawful-basis spec. |
| [testing/](testing/), [deployment/](deployment/), [disaster-recovery/](disaster-recovery/) | Test/lint, install/update, recovery. |

## ADRs (per-repo numbering)

| ADR | Decision |
| --- | --- |
| [0001](decision-records/ADR-0001-local-bulk-plane-cloud-keeps-webhooks.md) | Local PowerShell pipeline as the bulk-compute plane; cloud Pipeline keeps webhooks. |
| [0002](decision-records/ADR-0002-certificate-rooted-unattended-execution.md) | Certificate-rooted unattended execution + read-only-by-default grant. |
| [0003](decision-records/ADR-0003-short-lived-entra-token-postgres.md) | Short-lived Entra token for Postgres (no stored DB password). |
| [0004](decision-records/ADR-0004-vectorization-local-orchestration.md) | Vectorization: local orchestration, pinned pluggable embedding provider. |
| [0005](decision-records/ADR-0005-source-catalog-and-table-naming.md) | Source bronze catalog + table-naming reconciliation. |
| [0006](decision-records/ADR-0006-itglue-documentation-relationship-hub.md) | IT Glue as a documentation + relationship hub in the ingestion path. |
| [0007](decision-records/ADR-0007-installed-powershell-module.md) | Package as an installed PowerShell module (cmdlet-first). |
| [0008](decision-records/ADR-0008-golden-states-and-drift.md) | Golden states + drift detection for security-posture policies (+ Secure Score). |

Cross-reference sibling ADRs **by repo name** — ADR numbers are per-repo, not global.
