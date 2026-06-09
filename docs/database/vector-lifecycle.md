# Vector lifecycle

All embedding/vectorization runs on the home node (ADR-0004). This documents the lifecycle
the standard requires (front-end `CLAUDE.md §8`). The **target schema is front-end
`db/migrations/0045` + ADR-0041** (`ImperionCRM`) — this repo writes into it.

- **Target tables:** gold **`knowledge_object`** (one per entity: `tenant_id, entity_type,
  entity_ref, title, body, summary, source, content_hash, metadata`) → **`knowledge_embedding`**
  (chunked vectors: `chunk_index, chunk_text, embedding vector(1024), embedding_model, dimension,
  chunking_version, content_hash, token_count`, HNSW cosine index). The pipeline SP role has
  `SELECT/INSERT/UPDATE` on both + `DELETE` on `knowledge_embedding` (to prune superseded
  versions); the backend agent reads them.
- **What gets embedded:** the `body`/`summary` of gold knowledge objects across **CRM and
  support** (accounts, contacts, devices, proposals, contracts, tickets, exposures, assessments,
  security-posture, IT Glue/Azure operational docs) — coverage is the goal.
- **Pinned model (ADR-0041):** **Voyage AI `voyage-3-large` at dimension 1024**, system-wide —
  Anthropic's recommended embeddings provider for Claude RAG. Embeddings are decoupled from the
  generation model (Claude reads retrieved *text*, not vectors), so this is a retrieval/cost/
  governance choice. Stored as `embedding_model='voyage-3-large'`, `dimension=1024` on every row.
- **Provider:** provider-agnostic router; a local on-prem model (Ollama/ONNX, zero client-data
  egress) is swappable behind the same interface via a **versioned re-embed** — a *same-dimension*
  model swap is in-place-versioned; a *dimension* change needs a new `vector(N)` column (front-end
  migration).
- **Chunking:** documented `chunk_size` / `overlap`, versioned as `chunking_version` (start `v1`).
- **Idempotency:** unchanged `content_hash` → no re-embed (no re-billing).
- **Re-embed:** a model/chunking change is a **versioned re-embed**, never in-place — write the
  new `(embedding_model, chunking_version)` rows alongside the old.
- **Retention:** old vector versions retained until the new version is verified, then pruned
  (the SP's `DELETE` on `knowledge_embedding`).
- **Cost telemetry:** rows in, chunks, tokens, provider, model, cost, duration per batch.

> Built later (build-order task 8). This doc is the contract the embedding job implements; the
> schema it writes into is live (front-end 0045).
