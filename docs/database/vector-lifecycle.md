# Vector lifecycle

All embedding/vectorization runs on the home node (ADR-0004). This documents the lifecycle
the standard requires (front-end `CLAUDE.md §8`).

- **What gets embedded:** gold knowledge objects + selected silver text across **CRM and
  support** (accounts, contacts, proposals, contracts, tickets, IT Glue/Azure operational
  docs) — coverage is the goal so the agent is aware of everything.
- **Chunking:** documented `chunk_size` / `overlap`, versioned as `chunking_version`.
- **Model pinning:** one `embedding_model` + `dimension` system-wide (must match the
  backend agent's query path). Stored on every vector row.
- **Provider:** provider-agnostic router (Azure OpenAI / OpenAI / Claude); local model
  (Ollama/ONNX) swappable behind the same interface.
- **Idempotency:** unchanged `content_hash` → no re-embed (no re-billing).
- **Re-embed:** a model/chunking change is a **versioned re-embed**, never in-place.
- **Retention:** old vector versions retained until the new version is verified, then pruned.
- **Cost telemetry:** rows in, chunks, tokens, provider, model, cost, duration per batch.

> Built later (build-order task 8). This doc is the contract the embedding job implements.
