# ADR-0004: Vectorization: local orchestration, pinned pluggable embedding provider

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-08 |
| **Deciders** | Mark (human), Claude Code |
| **Amended by** | ADR-0009 (provider-agnostic "pluggable" framing retired; local-orchestration + pinned-contract core implemented as designed) |
| **Cross-references** | — |

## Problem

Embedding generation is the heaviest, burstiest, most cost-sensitive stage and the reason
the pipeline moved off the website. The front-end AI agents must become aware of **all**
company data (CRM + support), which means embedding the full gold corpus. Mark can read the
entire database locally and asked whether we can "embed with cloud models but process
locally."

## Options considered

None recorded in the original ADR.

## Decision

**Process locally, embed via a pinned, pluggable provider.**
- **Local orchestration:** reading the corpus, chunking, dedup-by-content-hash, batching,
  retry/backoff, rate-limit handling, cost accounting, and the `pgvector` upsert all run on
  the home node. Large backfills never touch Azure compute.
- **Pluggable embedding inference:** the embedding call goes through the provider-agnostic
  model router (Azure OpenAI / OpenAI / Claude). A **local model (Ollama/ONNX)** can drop in
  behind the same interface later — config, not code.
- **Pin one model + dimension system-wide.** Store `embedding_model`, `dimension`, and
  `chunking_version` on every vector row. A model change is a **versioned re-embed**, never
  an in-place overwrite.
- **Idempotency:** unchanged content hash → no re-embed (never re-bill identical text).

## Consequences

### Security impact

- **Security impact:** with a cloud provider, gold text leaves the network for the
  embedding call — covered by the provider's data terms; a local model keeps it on-prem.

### Cost impact

- **Cost impact:** orchestration is free (owned hardware); only inference tokens are billed,
  and only for changed content.

### Operational impact

- **Operational impact:** the pinned model is a system-wide contract with the backend
  agent's query path — coordinate any change across repos.

## Future considerations

- **Future considerations:** evaluate a local embedding model to drop inference cost to zero.

## Cross-references

This repo `CLAUDE.md §7`; front-end `CLAUDE.md §4` (gold layer), backend agent query path;
[database/vector-lifecycle.md](../database/vector-lifecycle.md).
