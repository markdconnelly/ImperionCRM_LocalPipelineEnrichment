# Documentation — ImperionCRM_LocalPipelineEnrichment

The on-prem PowerShell pipeline plane. Documentation is a **required deliverable and a
security control** — code without docs is incomplete (system-wide `CLAUDE.md`). This tree
mirrors the system-wide standard.

## Start here
1. [`../CLAUDE.md`](../CLAUDE.md) — the working brief (boundary, cert trust chain, per-client
   onboarding-app access, sources, vectorization, build order).
2. [`../README.md`](../README.md) — the onboarding elevator version (scheduled-task topology +
   medallion diagrams).
3. **Consolidated guides:** [collector inventory](collector-inventory.md) ·
   [vectorization → gold](vectorization-to-gold.md) · [IT Glue hub](it-glue-hub.md) ·
   [security-posture bronze](security-posture-bronze.md).
4. [`decision-records/`](decision-records/) — the ADRs (ADR-0001 … ADR-0027).

## Map of this tree

| Area | What lives here |
| --- | --- |
| [architecture/](architecture/) | [System overview](architecture/system-overview.md) + the cloud/local boundary + the domain roster + diagrams. |
| **Onboarding guides (root)** | [collector-inventory.md](collector-inventory.md) (every source → cmdlet → bronze → cadence → ADR) · [vectorization-to-gold.md](vectorization-to-gold.md) · [it-glue-hub.md](it-glue-hub.md) · [security-posture-bronze.md](security-posture-bronze.md). |
| [security/](security/) | [Certificate trust chain](security/certificate-trust-chain.md) · [least-privilege grants](security/least-privilege-grants.md) · [unified security standard](security/unified-security-standard.md) (system baseline — referenced, not restated). |
| [integrations/](integrations/) | One doc per source (33+): see [integrations/README.md](integrations/README.md) for the grouped index (CRM/support · RMM/managed estate · security · finance · logistics · scoped interaction). |
| [database/](database/) | [Medallion + write path](database/medallion-and-write-path.md) · [IT Glue→Postgres relationships](database/itglue-to-postgres-relationships.md) · [golden states & drift](database/golden-states-and-drift.md) · [vector lifecycle](database/vector-lifecycle.md) · [front-end schema handoff](database/front-end-schema-handoff.md). |
| [operations/](operations/) | [Scheduled-task registry](operations/scheduled-task-registry.md) · [change detection](operations/change-detection.md) · [cert rotation](operations/certificate-rotation.md) · [secret rotation](operations/secret-rotation.md) · [Azure PG firewall/IP](operations/azure-postgres-firewall.md) · [DNS golden approval](operations/dns-golden-approval.md). |
| [deployment/](deployment/) | [Unattended bring-up](deployment/unattended-bringup.md), install/update. |
| [data-governance/](data-governance/) | Provenance + lawful-basis spec. |
| [testing/](testing/), [disaster-recovery/](disaster-recovery/) | Test/lint, recovery. |
| [STATUS.md](STATUS.md) | Current build state (volatile detail). |

## ADRs (per-repo numbering)

| ADR | Decision |
| --- | --- |
| [0001](decision-records/ADR-0001-local-bulk-plane-cloud-keeps-webhooks.md) | Local PowerShell pipeline as the bulk-compute plane; cloud Pipeline keeps webhooks. |
| [0002](decision-records/ADR-0002-certificate-rooted-unattended-execution.md) | Certificate-rooted unattended execution + read-only-by-default grant. |
| [0003](decision-records/ADR-0003-short-lived-entra-token-postgres.md) | Short-lived Entra token for Postgres (no stored DB password). |
| [0004](decision-records/ADR-0004-vectorization-local-orchestration.md) | Vectorization: local orchestration, pinned embedding provider. |
| [0005](decision-records/ADR-0005-source-catalog-and-table-naming.md) | Source bronze catalog + table-naming reconciliation. |
| [0006](decision-records/ADR-0006-itglue-documentation-relationship-hub.md) | IT Glue as a documentation + relationship hub in the ingestion path. |
| [0007](decision-records/ADR-0007-installed-powershell-module.md) | Package as an installed PowerShell module (cmdlet-first). |
| [0008](decision-records/ADR-0008-golden-states-and-drift.md) | Golden states + drift detection for security-posture policies (+ Secure Score). |
| [0009](decision-records/ADR-0009-settled-embedding-stack-voyage-direct.md) | Settled embedding stack: Voyage `voyage-3-large` @ 1024, called directly. |
| [0010](decision-records/ADR-0010-posture-silver-bulk-merge.md) | Posture silver bulk merge (classify + roll up tenant posture). |
| [0011](decision-records/ADR-0011-quarterly-posture-snapshots.md) | Quarterly immutable posture snapshots (Imperion Secure Score). |
| [0012](decision-records/ADR-0012-local-service-account-identity.md) | Local service-account identity for the scheduled tasks. |
| [0013](decision-records/ADR-0013-meta-business-manager-ingestion.md) | Meta (FB/IG) Business Manager ingestion. |
| [0014](decision-records/ADR-0014-quickbooks-online-payment-fact.md) | QuickBooks Online payment fact. |
| [0015](decision-records/ADR-0015-receipt-blob-90-day-lifecycle.md) | Receipt-blob 90-day lifecycle. |
| [0016](decision-records/ADR-0016-okf-semantic-drift-agent.md) | OKF semantic-drift agent. |
| [0017](decision-records/ADR-0017-mileiq-drive-pull.md) | MileIQ business-drive pull. |
| [0018](decision-records/ADR-0018-rmm-managed-estate-sources.md) | RMM / managed-estate sources (Datto RMM/BCDR, myITprocess, UniFi). |
| [0019](decision-records/ADR-0019-security-incident-correlation-posture.md) | Security incident + Purview compliance correlation posture. |
| [0020](decision-records/ADR-0020-finance-qbo-full-data-pull-bi.md) | Finance: full QuickBooks Online data pull for BI. |
| [0021](decision-records/ADR-0021-logistics-procurement-amazon-cdw.md) | Logistics / procurement (Amazon Business, CDW). |
| [0022](decision-records/ADR-0022-scoped-interaction-collector.md) | Scoped interaction collector (allowlisted-principal ↔ client mail / Teams). |

Cross-reference sibling ADRs **by repo name** — ADR numbers are per-repo, not global.
