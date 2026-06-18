# ADR-0025: Consume the vendored vector contract; drop the hard-coded Get-ImperionVectorContract values

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-18 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | front-end ADR-0102 (the contract home — authoritative), front-end ADR-0041 (gold vector store), this repo ADR-0009 (vectorization), backend ADR-0075 (the sibling consumer); resolves #231; front-end #892 |

## Problem

`Get-ImperionVectorContract` hard-coded the pinned vector contract — model, dimension,
chunking policy, Voyage API shaping, and cost rate. These same values were also declared in
the backend (`VECTOR_CONTRACT`) and the front-end schema (migration 0045's `vector(1024)`). A
bump meant three coordinated, easily-forgotten edits; if this on-prem copy was missed, the
vectorizer would silently embed into a different space than the backend queries.

The front end now publishes the contract in ONE machine-readable home
(`ImperionCRM/db/contracts/vector-contract.json`, front-end ADR-0102). This repo — which owns
ALL vectorization (§7) — must consume that single source of truth.

## Decision

Vendor a **byte-identical copy** of the canonical contract at
`src/ImperionPipeline/Private/vector-contract.json` (it ships with the module — the installer
copies the module tree recursively) and have `Get-ImperionVectorContract` read + project it:

- The cmdlet reads the vendored JSON, **fails loud** if it is absent or malformed, and
  projects it into the **same flat `[pscustomobject]`** shape it returned before
  (`EmbeddingModel`/`Dimension`/`ChunkingVersion`/`MaxChunkChars`/`OverlapChars`/`ApiBatchSize`/
  `ApiBaseUri`/`UsdPerMillionTokens`). Every caller (`Get-ImperionVoyageEmbedding`,
  `Split-ImperionTextChunk`, `Invoke-ImperionVectorizeKnowledge`) is unchanged.
- A CI step (`build/Test-VectorContractSync.ps1`, run in `ci.yml`) fetches the front-end
  canonical (raw URL — both repos are public) and fails the build if the vendored copy has
  drifted. A contract bump in the front end therefore turns this repo's CI red until it
  re-vendors; that enforcement is what makes "one home" real across repos.

To change the contract: edit the front-end home, then re-vendor here (copy the canonical over
`src/ImperionPipeline/Private/vector-contract.json`). Never edit the values in place — a
model/chunking change is a system-wide versioned re-embed (this repo's ADR-0009 / front-end
ADR-0041 / ADR-0102).

## Consequences

### Security impact

None new. The vendored file is public contract shape only — no secrets, no PII, no client
identifiers (the Voyage key remains the SecretStore secret `embedding-provider-key`, §7). The
fail-loud read turns a missing/corrupt contract into a hard error rather than a silent embed
into the wrong vector space.

### Cost impact

None. No new dependency. Prevents the real latent cost of drift — embedding into a space the
backend does not query, which would force a corrective (billed) re-embed.

### Operational impact

No runtime behaviour change — the projected values are identical, now sourced from the vendored
home. The only new behaviour is the CI drift gate. The front-end home is front-end #892 /
ADR-0102; the backend cutover is backend #210 / ADR-0075.
