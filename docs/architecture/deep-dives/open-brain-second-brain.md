# Deep dive — the OpenBrain second-brain structure, realized as tiered knowledge memory

> **Where this sits.** A rabbit-hole companion to the front-end canonical synthesis
> [`how-it-all-fits-together.md`](https://github.com/markdconnelly/ImperionCRM/blob/main/docs/architecture/deep-dives/how-it-all-fits-together.md)
> and the public papers
> ([executive summary](https://github.com/markdconnelly/ImperionCRM/blob/main/public/papers/executive-summary.html) ·
> [research paper](https://github.com/markdconnelly/ImperionCRM/blob/main/public/papers/research-paper.html)).
> It lives in **this** repo because the on-prem enrichment plane does **all** the synthesis,
> summarization, vectorization, and consolidation that turns captures into a navigable brain (the
> "hippocampus", `CLAUDE.md §1`). Its sibling is
> [`mempalace-memory-architecture.md`](mempalace-memory-architecture.md) (the vector-recall half).

## What we borrowed — pattern, not package

[**OpenBrain / OB1**](https://github.com/NateBJones-Projects/OB1) ("Open Brain — The
infrastructure layer for your thinking. One database, one AI gateway, one chat channel — any AI
plugs in. No middleware, no SaaS") is the reference we benchmarked the *second-brain structure*
against. Its load-bearing ideas:

- **One database, many surfaces.** A single PostgreSQL store with vector search; every connected
  AI agent reads and writes the *same* brain, so value compounds across surfaces. Data is
  *synthesized in Postgres*, not scattered across SaaS silos.
- **Synthesis over storage.** Raw "thoughts" are mined by recipes ("Panning for Gold,"
  "Research Synthesis") into findings; entity-extraction workers build a **knowledge graph** with
  typed reasoning edges and entity wikis. The signature surface is a **universal memory MCP**
  exposing `store` / `recall` / `list_agents`.

**Imperion borrows the structure, not the codebase** — same reason as MemPalace: the whole thesis
is *one governed brain* under *one* RLS model, not a second store bolted alongside the medallion.
OB1 has no native canon/company/personal tiering; Imperion adds that, because an MSP's brain must
keep client-shared canon, company knowledge, and an employee's private second brain on **different
sides of a permission wall**. We re-implement OB1's "one synthesized brain + universal MCP"
pattern on Postgres + pgvector + Azure Blob, governed by the two-axis RLS access spine.

## The three tiers — canon · company · personal (6 personal brains)

The tiered-knowledge architecture (epic #966) gives the brain three concentric scopes, each with
a different authority and a different reader:

| Tier | What it holds | Authority / wall | Reader |
|---|---|---|---|
| **Canon** | Curated meaning shared across the org and clients — the OKF semantic layer, doctrine, ADRs | Front-end owned (ADR-0086); one home, zero drift | Everyone (role-scoped) |
| **Company** | Operational knowledge the company shares — the gold `knowledge_object` corpus over silver | Company axis of RLS (ADR-0105) | Any identified employee, role-scoped |
| **Personal** | A per-employee private second brain — **6 personal brains**, one per owner | **Owner axis** of RLS — owner-private by default | The owner (+ a ledgered curator) |

The **two-axis RLS access spine** (FE ADR-0105, #967) is what makes three tiers safe on one
database: a **company axis** (role-scoped company knowledge) and an **owner axis** (owner-scoped
personal knowledge). A row with `owner_user_id` set is owner-private; `owner_user_id IS NULL` is
the company axis (e.g. a shared agent diary). Personal→company is **not** an ambient capability —
it is an explicit, ledgered curation path with a service identity (the promotion wall, #967 §3c).
This is the structural difference from OB1's flat "everyone shares the same thoughts table."

## The Personal Knowledge Store (FE ADR-0114) — two substrates, not one medallion

The personal tier's load-bearing decision is that it is **two substrates with distinct jobs** —
inverting the original "bronze-verbatim-in-blob" sketch (#968):

### Substrate 1 — the Synthesis Store (Postgres) — OpenBrain-style

The system of record and the queryable/retrievable half. Three layers:

1. **Captures (immutable).** The raw verbatim the owner feeds the brain — notes, captured
   conversations, deliberate "remember this" writes. Append-only; never edited in place. (Capture
   unifies onto the verbatim `memory_drawer`, FE ADR-0113 / migration 0167.)
2. **Knowledge Facts — a temporal knowledge graph.** Captures are *synthesized* into typed facts
   with **Validity Windows** — each fact carries `valid_from` / `valid_to`, so the brain models
   *what was true when*, not just what is true now. This is the OB1 entity-graph idea made
   temporal: a fact can be superseded without being deleted, and recall can ask "as of date X."
3. **pgvector embeddings.** Facts/captures are embedded into the **same pinned vector space** as
   the company gold (Voyage `voyage-3-large` @ 1024, ADR-0041/0102) — so personal recall uses the
   *same* hybrid ranker as company recall (see
   [`mempalace-memory-architecture.md`](mempalace-memory-architecture.md), §3). One space, one
   ranker, two axes of RLS deciding who sees what.

**Why Postgres, not blob, for the verbatim?** The owner-scoping privacy contract is Postgres RLS
(ADR-0105). Re-implementing that on blob (SAS prefixes) for the *most sensitive* tier would be a
second enforcement mechanism on the data that least tolerates a gap. So raw verbatim is a
Postgres Capture; blob holds only the *curated projection* (below).

### Substrate 2 — the Curated Vault (Azure Blob per owner + a local synced folder)

A **markdown-only filesystem**, agent-curated and human-reviewable — the navigable "memory
palace" the owner actually reads and edits, and a fast context-load for the Jarvis orchestrator.
Binary artifacts (images/audio) land here with a routing record back into the Synthesis Store's
distillation. This is the half a human can browse like notes; the Synthesis Store is the half a
query runs against.

> **Provisioning status (assume available).** The per-owner personal storage accounts / Blob
> containers (`vault-<owner>`) are **provisioned and permission-granted**: per-owner
> `Storage Blob Data Contributor` scoped to the owner's own container only, plus the
> `imperion-personal-curator` user-assigned identity with Contributor across all owner vaults
> (the curator's god-view, below). Document them as **live**. The local synced folder is an
> rclone-style mirror of the owner's blob vault.

### The bidirectional Personal Curator

A background service with a **ledgered god-view** keeps the two substrates in sync **both ways**:
synthesizes new Captures into Knowledge Facts and projects them into the Curated Vault markdown;
and folds the owner's hand-edits in the Vault back into the Synthesis Store. It also **hunts
Knowledge Contradictions** — facts whose Validity Windows or claims conflict — and surfaces them
for **owner approval** rather than silently resolving them. The "ledgered god-view" is the
critical control: the curator can read owner-private data (it must, to synthesize), but **every**
such read is appended to an audit ledger, so an autonomous curator never becomes a silent
superuser (this is the amendment ADR-0114 makes to ADR-0105). The curator runs under the
non-`BYPASSRLS`, non-superuser `imperion-personal-curator` Postgres login with explicit god-view
grants — capability is granted, not inherited.

## The write/recall surface — the Universal Memory MCP (FE ADR-0116)

OB1's signature is a universal memory MCP. Imperion ships the same shape — `store` / `recall` /
`list_agents` — so the tools an engineer actually builds *with* (Claude Code, Cursor) **and** the
runtime orchestrator share **one** governed brain. The decisions that make it safe against a prod
store of client PII:

- **Thin client over backend HTTP, not a read-write pg-MCP.** The MCP server is a protocol
  adapter; `POST /api/memory/{store,recall}` + `GET /api/memory/agents` carry the logic,
  Easy-Auth + caller-allowlist gated (backend ADR-0035), RLS enforced server-side via
  `withIdentity`. A Cursor-reachable surface that spoke arbitrary SQL against prod PII would be
  unbounded; the read-only pg-MCP (`CLAUDE.md §8`) is safe *because* it is read-only. Also,
  `recall` needs a Voyage embedding — an AI call — which must be backend (no front-end AI key,
  ADR-0043).
- **Identity = the human's Entra claims, end-to-end.** The local stdio MCP mints a short-lived
  token via the `az` CLI for the backend API audience (the pg-mcp pattern), and the human's
  claims flow through to RLS. No stored secret on the edge.
- **`store` → `memory_drawer`, attributed by `agent_slug`.** A deliberate "remember this" is
  neither a transcript turn nor a GUI note, so §4 is reframed from *non-agent* to *non-transcript
  deliberate capture*, and a nullable `agent_slug` column records which agent held the pen.
- **The MCP write surface is personal-scope only.** Every MCP `store` is
  `owner_user_id = <authenticated human>`. An external client **cannot** write a NULL-owner
  shared/agent diary — those are written backend-in-process by autonomous agents. So a compromised
  Cursor can only poison its own user's personal memory (which only ever grounds that user), and
  the personal→company promotion wall stays intact for free. **`recall` reads *across* diaries**
  (RLS-permitted) — that is how a per-agent diary becomes consultable.
- **`recall` = the single canonical gold ranker** (FE ADR-0115) — no throwaway fallback path. It
  is **deploy-dormant until its deps land: Backend #304 (query-embed) + LP #300 (gold summaries)
  + LP #176 (embedding hydration)** — all three are this system's responsibility, and **LP #300 /
  LP #176 are owned by this repo.** Dormancy is acceptable because the entire pre-go-live system
  is deploy-dormant by design.

## This repo's role — the engine under the brain

The tiers, the MCP, and the RLS are front-end/back-end surfaces. **The synthesis is on-prem.**
This repo is what makes the second brain *real* rather than a schema:

- **It is the sole embedder.** Personal Captures and Knowledge Facts embed into the same pinned
  Voyage @ 1024 space as company gold — produced here (`CLAUDE.md §7`, ADR-0009). **Embedding
  hydration for the unified-memory recall path is LP #176**; **gold summaries are LP #300**. Until
  they run, the Universal Memory MCP `recall` tool is dormant (FE ADR-0116 names them as deps).
- **It does the synthesis/consolidation pass.** The nightly `Invoke-ImperionKnowledgeSync`
  (04:30) composes silver facts into gold knowledge and encodes them for recall — the "sleep-time
  consolidation" that grows the company tier; the same machinery extends to personal-tier
  synthesis.
- **It keeps canon honest.** `Invoke-ImperionSemanticDriftSync` (#175/#249) detects
  live-silver-vs-OKF-bundle drift (the **canon** tier's meaning) and *proposes* a sync against the
  front-end OKF bundle — column **names** and source-of-record/authority only, no data, no PII,
  dry-run by default, humans approve. A cross-repo **okf-sync** CI gate (#245) enforces that a
  bronze-ingestion change links an OKF concept update.

Per-tenant and per-owner isolation are absolute throughout: every row carries its owning
tenant/owner; no cross-tenant read in any query path; the owner axis is owner-private by RLS; the
curator's god-view is ledgered. **Never commit secrets** — every credential lives in Key Vault,
custodied server-side; this plane handles only names, thumbprints, and aggregate counts.

## See also

- [`mempalace-memory-architecture.md`](mempalace-memory-architecture.md) — the vector-recall
  half (single pinned space, two-level recall, the gold hybrid ranker).
- Front-end ADRs: **0105** (two-axis RLS access spine) · **0113** (verbatim memory tier) ·
  **0114** (Personal Knowledge Store) · **0115** (gold hybrid ranker) · **0116** (Universal
  Memory MCP). Epics **#966** (tiered knowledge) · **#1152** (personal-store build) · **#1169**
  (unified-memory build).
- This repo: **ADR-0009** (settled embedding stack) · **ADR-0016** (OKF semantic-drift agent) ·
  **ADR-0028** (per-tenant credential resolution).
- The superiority argument:
  [`data-design-for-agents.md`](https://github.com/markdconnelly/ImperionCRM/blob/main/docs/architecture/data-design-for-agents.md).
