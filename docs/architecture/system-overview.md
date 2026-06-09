# Architecture — on-prem pipeline plane

The fourth repo in the Imperion CRM system: an **on-prem, PowerShell, scheduled-task**
ingestion/enrichment/vectorization engine. Outbound-only; no inbound surface. Writes the
shared PostgreSQL + pgvector DB the website reads and the backend agent queries.

## Context (cloud/local boundary — ADR-0001)
```mermaid
flowchart LR
    subgraph CLOUD["Azure"]
      FE["ImperionCRM (web app)"]
      BE["ImperionCRM_Backend (agent, sends)"]
      PL["ImperionCRM_Pipeline (webhooks only)"]
    end
    subgraph HOME["Home server (this repo)"]
      T1["Entra SPs → IT Glue"]
      T2["Azure + Sentinel inventory → IT Glue"]
      T3["IT Glue full export → Postgres"]
      T4["Kaseya quotes/proposals/contracts/tickets"]
      T5["Transforms + vectorization"]
    end
    SRC["M365 (GDAP) · Azure ARM · IT Glue · Autotask · KQM · DocuSign · Apollo · website"]
    SRC --> HOME
    HOME --> PG[("PostgreSQL + pgvector")]
    PL --> PG
    FE --> PG
    PG --> BE
```

## Trust & data flow
- **Auth:** one machine cert → unlocks SecretStore + is the Entra app credential
  ([security/certificate-trust-chain.md](../security/certificate-trust-chain.md)).
- **Ingestion pattern:** flatten → (IT Glue document + relate) → Postgres bronze
  ([database/medallion-and-write-path.md](../database/medallion-and-write-path.md), ADR-0006).
- **DB:** short-lived Entra token, TLS, table-scoped role (ADR-0003).
- **Change detection:** content hash + watermark — "if nothing changed, move on"
  ([operations/change-detection.md](../operations/change-detection.md)).
- **Vectorization:** local orchestration, pinned pluggable provider (ADR-0004).

## Required diagrams (to add under [../diagrams/](../diagrams/))
high-level (above) · application (module map) · infrastructure (home node + Azure) · data
flow (medallion) · security (trust chain) · agent (N/A — cross-ref backend) · integration
(per-source) · deployment (task registration). Mermaid source committed.
