# ADR-0018: RMM / managed-estate sources — Datto RMM, Datto BCDR, myITprocess (+ device-precedence revisit)

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed |
| **Date** | 2026-06-15 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0005; ADR-0006; ADR-0012; frontend ADR-0039; frontend ADR-0017; pipeline ADR-0009 |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as `ADR-0018`; the
> orchestrator renames this file to the next free local-pipeline ADR number at merge and
> fixes every reference. Do not reserve a number now.

> **Scope of this ADR is DESIGN ONLY.** The collectors are **gated on the front-end bronze
> migration** (frontend #674 → migration `0119`), which is authored concurrently and is
> **not merged yet**. This ADR records the design + decisions; the collector cmdlets ship in
> a follow-up (the **collector phase of issue #195**, which stays open) once `0119` merges.
> This repo never creates tables (§5/§6, ADR-0005) — it fails loudly on a missing one.

## Problem

Imperion's source catalog (epic #194) does not yet capture the **managed estate** —
the RMM/backup/strategic-advisory picture an MSP runs day to day. Three sources hold it:

- **Datto RMM** — the live device inventory: every managed endpoint, its **patch state**,
  and its **asset / software inventory**. This is a *strong* device authority, distinct from
  the m365 (Intune/Entra) and IT Glue device views already in the catalog (§5).
- **Datto BCDR / backup** — **backup posture per device**: protected / unprotected,
  last-good-backup, last-screenshot-verification — the answer to "is this machine actually
  recoverable?".
- **myITprocess** — **strategic roadmap / QBR / assessment recommendations**, scoped to the
  **account** (not the device): the vCIO advisory layer (initiatives, alignment scores,
  recommendations) that feeds account health and QBR narrative.

Without these the orchestrator agent is blind to whether a managed device is patched, backed
up, and on a strategic roadmap — a gap (§1: "coverage is the goal; gaps are bugs"). Datto
RMM in particular forces a **device-merge precedence revisit**: it is a more authoritative
machine-truth source than the existing device sources, so the silver device merge must place
it explicitly.

## Context

- **Schema is front-end-owned (system CLAUDE.md §1, ADR-0005).** The physical bronze tables
  are defined by **frontend migration `0119`** (frontend #674), not here. This repo is a
  **producer only**: it writes the migration-defined tables and **fails loudly** if one is
  absent (ADR-0005 §4). No DDL is defined in this ADR.
- **Existing device-merge precedence.** The silver `device` entity is recomputed by
  **precedence**, manual `website_*` highest, machine sources below
  (`m365`, `itglue`, `website` today — §5, `docs/database/medallion-and-write-path.md`). The
  anchor is **frontend ADR-0039** (per-source bronze + the `website` **resurrection guard** —
  manual web-app rows outrank every machine source and resurrect a record a machine source
  dropped) and **pipeline ADR-0009**. Datto RMM has to slot **into the machine tier of that
  ordering** without touching the `website` guard.
- **Auth is a SecretStore API key per source** (§2/§4) — these are MSP-wide vendor keys
  (like Autotask / IT Glue / KQM), **not** per-employee OAuth (contrast ADR-0017 MileIQ) and
  **not** per-client onboarding-app tokens (§3, those are the m365 path). The connect layer
  resolves each from the vault; a missing key → the task logs + exits clean (dormant/gated).
- **IT Glue relationship (ADR-0006).** These sources describe the **managed estate** —
  configurations, organizations, contacts, devices — so they are **operational/infrastructure
  data** and belong on the flatten → IT Glue → Postgres path (ADR-0006 scope), relating Datto
  devices to their IT Glue Organization / Configuration / primary Contact. myITprocess is the
  borderline case (strategic, account-scoped) and is discussed under Decision.

## Options considered

1. **One ADR for all three RMM/managed-estate sources + the device-precedence revisit; FE
   migration `0119` first; collectors as a gated follow-up.** *(Chosen.)* The three share
   auth model, IT Glue relationship, and the managed-estate framing; the precedence revisit is
   driven specifically by Datto RMM and belongs with it.
2. One ADR per source. Rejected — they ship together (epic #194 split is **by domain**, and
   this *is* the one domain); the precedence decision would be stranded from its driver.
3. Make Datto RMM the **top** device authority (above `website`). **Rejected** — it violates
   the resurrection-guard invariant (frontend ADR-0039): manual web-app entries must always be
   able to outrank and resurrect machine truth. Datto RMM is strong, but it is still a machine
   source.
4. Collectors in this ADR's PR (now). Rejected — blocked on `0119`; building against an absent
   table would only fail loudly (ADR-0005). Design now, build when the table exists.

## Decision

**Adopt the three RMM/managed-estate sources, design-only this phase, gated on frontend
migration `0119`. Revise the device-merge precedence to admit Datto RMM into the machine
tier, below `website`.**

### 1. Sources, bronze tables, IT Glue path

The **physical table names are owned by frontend `0119`** (frontend #674). This ADR
**references them by name** and the collectors will fail loudly if absent — it does **not**
define their DDL.

| Source | Logical key | Bronze table (frontend `0119`) | Grain | IT Glue path (ADR-0006) |
|---|---|---|---|---|
| Datto RMM | `datto_rmm` | `datto_rmm_devices` | device (+ patch state, asset/software inventory) | **Yes** — relate device → Organization / Configuration / Contact |
| Datto BCDR | `datto_bcdr` | `datto_bcdr_backups` | device backup posture | **Yes** — relate backup posture to the same device/Configuration |
| myITprocess | `myitprocess` | `myitprocess_recommendations` | account (roadmap / recommendation) | **No** — strategic/account data flattens straight to Postgres (ADR-0006 §2, the CRM/advisory exception) |

Each follows the canonical pattern (§6): pull → flatten to a flat `[PSCustomObject]` table →
(operational sources) document + relate in IT Glue → import the same flat shape to bronze,
upsert idempotent on `(tenant_id, source, external_id)`. Bronze over-collects (every attribute
the API exposes), silver narrows (§5 bronze rule). Each new collector is a **~15-line adapter**
over `Invoke-ImperionBronzePost` (the post-writer scaffold, `medallion-and-write-path.md`), not
a new copy of the scaffold.

### 2. Device-merge precedence revisit (the key decision)

Datto RMM becomes a **strong device authority alongside `m365` and `itglue`** — but **still
below `website`** (the resurrection guard, frontend ADR-0039, is untouched). The new silver
`device` precedence ordering is:

```
website  >  datto_rmm  >  m365  >  itglue
```

Justification for where Datto RMM slots among the machine sources:

- **Below `website`** — non-negotiable. Manual web-app entries are the resurrection guard
  (frontend ADR-0039): they outrank and can resurrect any machine source. Datto RMM never
  overrides a manual entry.
- **Above `m365` and `itglue`** for the **device-existence + live-state** facts (is this
  device real, online, patched, what software/assets does it carry). Datto RMM is the
  **purpose-built RMM agent on the endpoint** — it is the freshest, most complete machine
  truth about the managed estate, more authoritative than the Intune/Entra (`m365`) view
  (which sees only enrolled devices) and far more authoritative than `itglue` (documentation,
  human-maintained, drifts).
- **`itglue` stays lowest** of the machine sources — it is documentation, not telemetry.

This ordering is **field-scoped, not wholesale**: per the merge contract, a higher-precedence
source wins a field **only where it actually populates it**. Datto BCDR contributes the
**backup-posture** fields to the device record (no other source carries them) and does not
otherwise compete for device-identity precedence. The normative ordering above and the BCDR
field-merge note must be reflected in `docs/database/medallion-and-write-path.md` (silver layer
section) **and proposed back to the front end** — the silver `device` **meaning** (source-of-
record / authority / joins) is OKF-bundle-owned in the front end (system CLAUDE.md §11), so the
matching concept file + `coverage-matrix.md` row update is filed as a front-end issue when this
lands (see Operational impact).

### 3. Connect layer, hermetic tests, naming

- **Connect-layer entries (planned, collector phase):** one shared request helper per vendor —
  `Invoke-ImperionDattoRmmRequest`, `Invoke-ImperionDattoBcdrRequest`,
  `Invoke-ImperionMyItProcessRequest` — each owning auth-header injection, the vendor's paging
  walk, retry/backoff, and log redaction (the `Invoke-ImperionQboRequest` pattern). Datto RMM
  uses an **API-key → short-lived bearer** exchange (its `/auth/oauth/token` endpoint); the
  helper owns that exchange and never logs the token.
- **Hermetic-test expectation:** every collector + connect helper ships Pester unit tests that
  **mock the HTTP boundary** (no live vendor call in CI) — flatten-shape assertions, paging
  termination, the API-key→bearer exchange, fail-loud-on-missing-table, and idempotent-upsert
  envelope. `PSScriptAnalyzer` lint green. Mirrors the siblings' lint+test gate (§4).
- **Naming (digit-prefix convention, §5):** none of these vendors lead with a digit, so the
  logical keys are spelled out — `datto_rmm`, `datto_bcdr`, `myitprocess` — no `m`-prefix
  needed (that rule exists only for digit-led keys like `m365`). Cmdlet nouns:
  `DattoRmm`, `DattoBcdr`, `MyItProcess`.

### 4. SecretStore secrets + rotation

Three **new MSP-wide vendor keys** join the vault (§2/§4), names added to
`config/secret-names.example.psd1` as stable constants (values added by the operator via
`Set-Secret`, **never** in the repo):

| Config key (PascalCase) | SecretStore title | Source system |
|---|---|---|
| `DattoRmmApiKey` | `Datto-RMM-API-Key` | Datto RMM (key + secret → bearer exchange; if the vendor issues a key/secret pair, a second `Datto-RMM-API-Secret` title) |
| `DattoBcdrApiKey` | `Datto-BCDR-API-Key` | Datto BCDR / backup |
| `MyItProcessApiKey` | `myITprocess-API-Key` | myITprocess |

Rotation follows the existing **`docs/operations/secret-rotation.md`** runbook (mint new → keep
overlap → `Set-Secret` → run task → revoke old); these three are added to that runbook's source-
key list in the collector-phase PR. No new rotation mechanism is introduced.

## Consequences

### Security impact

- **No secret values anywhere** (system CLAUDE.md §2). Only stable secret **names** are
  recorded; values live in the SecretStore (cert/CMS-unlocked, §2) and are added by the
  operator. **Never commit secrets.** Keys ride **headers / token-exchange bodies**, never a
  querystring; the connect helpers redact tokens and URLs from logs (the KQM/QBO idiom).
- These are **read-only** vendor pulls — no write surface back to Datto or myITprocess. The
  only write path is the existing **scoped, gated** IT Glue documentation write (ADR-0006 §5)
  for the operational sources; a net-new IT Glue write surface is a human-approval gate (§8).
- **180-day retention is out of scope here** — that is the **sibling #196** (Security-incidents)
  concern, not this managed-estate ADR.
- Device/backup data is operational, not client PII in the comms sense; standard tenant-tagging
  and per-tenant isolation (§3) apply — every row carries its owning tenant.

### Cost impact

- Negligible. Scheduled incremental page-walks per source; idempotent upsert on
  `(tenant_id, source, external_id)` avoids rewriting unchanged rows; no embedding cost at the
  bronze stage.

### Operational impact

- **Gated on frontend migration `0119` (frontend #674).** Collectors are authored in the
  **collector phase of #195** (issue stays open) and run live only once `0119` is merged +
  applied. Until then the design stands and no table is touched.
- **One scheduled task per (source, entity)** (§1) — `Imperion-DattoRmm-Devices`,
  `Imperion-DattoBcdr-Backups`, `Imperion-MyItProcess-Recommendations` — registered in
  `docs/operations/scheduled-task-registry.md` at the collector phase, run-as the local service
  account (ADR-0012).
- **Front-end follow-up (OKF + precedence):** the silver `device` precedence change and the
  Datto BCDR backup-posture field merge must update the front-end OKF `device` concept file +
  `coverage-matrix.md` (system CLAUDE.md §11); file a front-end issue at merge proposing it
  (parallels the schema-ownership rule — propose in the front end). New `myitprocess`
  account-advisory data may warrant its own silver concept (a front-end call).
- **Three integration docs** (`docs/integrations/datto-rmm.md`, `datto-bcdr.md`,
  `myitprocess.md`: auth, rate limits, cadence, fields, paging, retry) land in the collector-
  phase PR (§9 doc standard), plus the secret-rotation + scheduled-task-registry updates.

## Future considerations

- **Datto RMM patch state → posture / drift.** Patch compliance is a natural feed into the
  posture/drift model (ADR-0008/0010) — a future ADR could promote "patched vs out-of-date" to
  a golden-state-style verdict alongside the security-posture policies.
- **Backup posture as an account-health signal.** Datto BCDR "unprotected / stale-backup"
  counts roll up to account health / QBR (the myITprocess advisory narrative) — a silver/gold
  rollup is a follow-up once the bronze lands.
- **Confirm live shapes before LIVE.** The exact Datto RMM / BCDR / myITprocess response
  wrappers, paging params, and the API-key→bearer exchange are confirmed against the real APIs
  in the collector phase (the CONFIRM-BEFORE-LIVE list in each integration doc), same as the
  MileIQ precedent (ADR-0017).

## Cross-references

ADR-0005 (source catalog & table naming; fail-loud-on-missing-table) · ADR-0006 (IT Glue
documentation + relationship hub; operational-vs-CRM split) · ADR-0012 (local service-account
run-as identity) · frontend ADR-0039 (per-source bronze + `website` resurrection guard — the
device-precedence anchor) · frontend ADR-0017 (schema ownership — migrations are front-end-owned)
· pipeline ADR-0009 (per-source bronze + website-highest precedence). Issues: **#194** (epic —
source-catalog expansion, split by domain), **#195** (this child — ADR phase here, collectors
follow once frontend `0119` merges), **frontend #674** (bronze migration `0119`), **#196**
(sibling — security incidents + 180d retention, out of scope here).
