# ADR-0022: Scoped interaction capture — allowlisted principal ↔ client only, config-driven

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-16 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0001; ADR-0005; ADR-0006; ADR-0007; ADR-0018; ADR-0021; frontend ADR-0042; frontend ADR-0017; frontend ADR-0086 (OKF) |

> **Number claimed at merge (system CLAUDE.md §10.3).** Authored as `ADR-0022` (next free after
> 0021); the orchestrator confirms/renames this file + fixes every reference + the index row at
> merge if a concurrent branch took 0022 first. **Do not reserve a number now.**

> **Scope: ADR + collectors ship TOGETHER in this PR.** Like ADR-0021 (logistics), the front-end
> bronze migration `0120` (`bronze_batch_b`) is **already merged + prod-applied + verified**
> (`m365_email`, `m365_teams`), so the design **and** the collectors land in one PR. This repo
> never creates tables (§5/§6, ADR-0005) — it **fails loudly** on a missing one. The collectors are
> DORMANT until Graph mail/chat consent + the config-driven allowlist are provisioned (Mark).

## Problem

The silver `interaction` timeline (the account-history loop the orchestrator reasons over) has the
two bronze landing tables `m365_email` / `m365_teams` (front-end `0120`) but **no collector** feeding
them. Epic #194 splits the source-catalog expansion by domain; this is the **interaction-capture**
domain (child E, #199).

Mail and Teams chat are **PII-heavy and lawful-basis-sensitive** — capturing *all* employee mail
would be both noise and a governance problem. The capture must be **tightly scoped at the point of
collection**: only communications that are genuinely part of an account's history, and only for the
people whose client-facing communications we have a basis to retain. The scoping set must change
**without a code release** (people move in and out of the client-facing role).

## Context

- **Schema is front-end-owned (system CLAUDE.md §1, ADR-0005, frontend ADR-0017).** `m365_email` /
  `m365_teams` are defined by front-end migration `0120` — the canonical lossless envelope
  (`tenant_id`, `source`, `external_id` = the Graph message id, `collected_at`, `raw_payload jsonb`,
  `content_hash`) + curated flat columns. **Already prod-applied + verified**, so the collectors
  build now. **No DDL is defined here.** These are MESSAGE-grain tables, distinct from the older
  thread/chat-grain `m365_mail_messages` / `m365_teams_chats` (migration 0065, the broad
  `Get-ImperionM365Mail` path) — both coexist.
- **An existing broad collector is not the right tool.** `Get-ImperionM365Mail` /
  `Get-ImperionM365TeamsChat` keep any Imperion↔client *domain* cross (`Test-ImperionCrossOrgComm`)
  across env-listed mailboxes → `m365_mail_messages`. Issue #199 is **strictly tighter**: a
  two-person, config-driven principal allowlist AND a silver-resolved client counterpart, landing in
  the new `m365_email` / `m365_teams`. Reusing the broad collector would over-capture and miss the
  config-driven allowlist requirement.
- **Lawful-basis guardrail (CLAUDE.md §8, front-end consent gate).** Having a thread is never consent
  to contact; capture stays scoped + provenance-stamped. Filtering at collection (before bronze)
  keeps internal-only and non-client traffic out of the store entirely.
- **A home server behind NAT cannot receive Graph change notifications (ADR-0001 / frontend
  ADR-0042).** Scheduled bulk mail/chat pulls belong in this repo; latency-sensitive/inbound stays in
  the cloud plane.
- **Teams chat is a Microsoft protected API.** `/users/{id}/chats` + chat messages need Microsoft's
  protected-API approval on top of the permission grant (the existing m365-communications gate). The
  mail path goes first; the Teams task stays gated until approval.

## Options considered

1. **A new scoped collector pair (mail + Teams) with a config-driven two-person allowlist + a
   silver-resolved client counterpart, filtering at collection, landing in `m365_email`/`m365_teams`;
   ADR + collectors in one PR (FE `0120` already applied).** *(Chosen.)* Tightest fit to #199; reuses
   the canonical connect/get/post + `Invoke-ImperionBronzePost` pattern; the allowlist is data so the
   set changes without a release.
2. **Extend `Get-ImperionM365Mail` with an allowlist parameter.** Rejected — it targets the older
   `m365_mail_messages` (0065) at thread grain with a domain filter and env-var mailbox lists;
   bolting a config-driven two-person allowlist + silver counterpart resolution + a different target
   table onto it would overload one cmdlet and conflate two distinct capture policies. A separate,
   purpose-named collector keeps each policy legible.
3. **Hardcode the Derek/Mark allowlist in code.** Rejected — violates #199 (config-driven) and forces
   a code release + PR every time the client-facing set changes. The allowlist is machine config
   (`%ProgramData%\Imperion\`, ADR-0007 config-outside-the-module).
4. **Domain-only counterpart matching (no silver resolution).** Rejected — a domain list drifts from
   reality and would capture a stranger at a client domain. Resolving the counterpart against silver
   `contact`/`account` keeps capture aligned to known clients (exact-email is the tightest case;
   client-domain is the fallback for a known account whose individual sender is not yet a contact
   row).
5. **Capture everything, scope at silver.** Rejected — puts un-scoped PII in bronze, breaking the
   lawful-basis-at-collection guardrail (§8). Filter at collection, before anything lands.

## Decision

**Add a scoped interaction-capture collector pair that filters AT COLLECTION to keep ONLY
message-grain mail / Teams chat where (a) a CONFIG-DRIVEN allowlisted Imperion principal AND (b) a
known CLIENT counterpart (resolved against silver `contact`/`account`) are both participants. ADR +
collectors ship in one PR (FE `0120` already applied). Read-only Graph, no write authority. DORMANT
until consent + the allowlist config are provisioned (Mark).**

### 1. Bronze targets (FE-owned, front-end migration `0120` — already applied)

| Source entity | Bronze table (front-end `0120`) | `source` | external_id | Grain |
|---|---|---|---|---|
| Mail | `m365_email` | `m365_email` | Graph message id | message |
| Teams chat | `m365_teams` | `m365_teams` | Graph chatMessage id | message |

Lossless envelope; curated flat columns (`m365_email`: message/conversation id, subject, preview,
from_address, to_recipients, direction, sent_at, has_attachments, mailbox_owner; `m365_teams`:
message/conversation id, preview, from_user, participants, direction, message_type, sent_at,
has_attachments, captured_user). The full Graph object stays lossless in `raw_payload`.

### 2. The scope rule (filter at collection, before bronze)

A communication is captured **iff** over its participant addresses BOTH hold:
1. an **allowlisted principal** is a participant — the config-driven two-person set
   (`Test-ImperionScopedInteraction`); AND
2. a **client counterpart** is a participant — a participant whose exact address is a known silver
   `contact.email`, OR whose domain is a known client domain (`Resolve-ImperionClientContactSet`,
   reading `contact` JOIN `account`).

Drops by construction: internal-only threads; threads with a non-client external party and no client
counterpart; any thread not involving an allowlisted principal. The predicate is a pure function
(unit-tested in isolation); an allowlisted principal cannot satisfy both halves alone.

### 3. The allowlist is config, not code

The set of principals lives in a machine config json at
`%ProgramData%\Imperion\interaction-allowlist.json` (`Resolve-ImperionInteractionAllowlist`; override
via `$env:IMPERION_INTERACTION_ALLOWLIST` / `-AllowlistPath`). v1 = Derek Rankin + Mark Connelly, but
**no names are hardcoded** — only `upn` is read (case-insensitive). The file is **not committed**
(real UPNs are employee identifiers, `.gitignore`); only `config/interaction-allowlist.example.json`
ships. Absent/empty config → **dormant**: the collector logs and returns, capturing nothing (never
wide-open).

### 4. Naming + pattern

- Cmdlets: `Get-ImperionScopedInteractionMail` → `Set-ImperionScopedInteractionMailToBronze`;
  `Get-ImperionScopedInteractionTeams` → `Set-ImperionScopedInteractionTeamsToBronze`. Reuse the
  existing `Invoke-ImperionGraphRequest` connect helper (no new app reg, no new connection).
- Each collector follows the canonical pattern (§6): Graph page-walk → flatten to a flat
  `[PSCustomObject]` → bronze, **upsert idempotent on `(tenant_id, source, external_id)`**, **skip on
  unchanged `content_hash`**. Pure communication data → **straight to Postgres, IT Glue skipped**
  (ADR-0006). Post writers are ~15-line adapters over `Invoke-ImperionBronzePost` (`-ColumnSet`
  projection: a future collector field can never break the insert; extras survive in `raw_payload`).
- One scheduled task per (source, entity): `m365/scoped-interaction-mail`,
  `m365/scoped-interaction-teams`.
- **Hermetic tests:** every collector/writer/predicate/resolver ships Pester unit tests that **mock
  the Graph + DB boundary** (no live API/DB call in CI) — scope-predicate truth table, dormant-on-no-
  allowlist, flatten shape, idempotent-upsert envelope, `-WhatIf` gate. Fixtures are **synthetic** —
  no real client data or employee identity in code/tests. `PSScriptAnalyzer` clean.

### 5. Auth — read-only, the existing cert-SP Graph app

Reuses the module's cert-SP app-only Graph token (`Get-ImperionGraphToken`, ADR-0002 / pipeline
ADR-0018 onboarding-app, read-only grants) — **no new app registration, no write scope, no new
SecretStore secret**. Single-tenant against the Imperion company tenant by default; the per-client
onboarding-app fan-out (pipeline ADR-0018) is supported via `-TenantId` but deferred.

## Consequences

### Security impact

- **Read-only — no mail/chat write surface, ever.** The pull requests read scopes only.
- **PII scoped at collection (lawful basis).** Only allowlisted-principal ↔ client messages land;
  internal-only and non-client traffic never enters bronze. Rows are envelope-stamped
  `source`/`collected_at` for provenance; having a thread is **never** consent to contact (§8,
  front-end consent gate).
- **No secrets, no PII, no client identifiers in the repo (system CLAUDE.md §2).** The allowlist is
  config (un-committed; only an `.example.json` with placeholder UPNs ships); the Derek/Mark set is
  data, not a code literal. The structured logs record **counts only — never subjects, addresses,
  message content, or principal identity** (§8 never-log-the-fact). **Never commit secrets.**
- **Fail-closed.** No allowlist / no Graph access / missing table → log + clean exit, no silent
  retry, no wide-open capture.

### Cost impact

- Negligible ingest cost — low-volume scheduled page-walks scoped to two mailboxes; idempotent upsert
  + `content_hash` skip avoids rewriting unchanged rows; no embedding cost at the bronze stage.

### Operational impact

- **Gates to LIVE (BUILD is done — `0120` is applied):** (1) the **allowlist json** provisioned at
  `%ProgramData%\Imperion\interaction-allowlist.json`; (2) **Graph Mail.Read** consent for the
  principal mailboxes; (3) **Teams only** — Microsoft **protected-API approval** for `/chats` +
  messages. Each daily task logs + exits cleanly until its gate clears (deploy-ahead/dormant).
- **CONFIRM-BEFORE-LIVE.** The Graph `/messages` + `/chats/{id}/messages` field names, the
  `receivedDateTime` filter, the chat-member email path, and the direction heuristic are modeled from
  the documented API and UNVERIFIED until consent lands; misses land NULL, `raw_payload` keeps
  everything.
- **OKF + silver (system CLAUDE.md §11).** This PR touches **no silver entity shape** — `m365_email`
  / `m365_teams` are bronze landing tables (FE `0120`), not silver entities. **No OKF concept-file /
  coverage-matrix change is required here.** When the silver `interaction` entity is later wired to
  consume these (its source-of-record / join paths), that is **proposed back to the front end** (file
  an `ImperionCRM` issue then, parallel to the schema-ownership rule) — not authored cross-repo here.
- **Scheduled tasks:** `m365/scoped-interaction-mail`, `m365/scoped-interaction-teams` — added to
  `docs/operations/scheduled-task-registry.md`, run-as the local service account (ADR-0012).
  Integration detail in `docs/integrations/scoped-interaction-capture.md`.

## Future considerations

- **Silver `interaction` wiring.** Once bronze flows, a silver `interaction` rollup (mail + chat →
  one account-history timeline) and the OKF concept note are a front-end follow-up (propose then).
- **Allowlist growth.** The config-driven set can widen beyond two principals with zero code change —
  the dormant/empty path already handles 0..N principals.
- **Per-client onboarding-app fan-out.** The collectors accept `-TenantId`; pulling a client tenant's
  side via the onboarding app (pipeline ADR-0018) is a deferred extension.
- **Gold / embeddings.** Scoped interactions → gold knowledge objects the orchestrator reasons over
  (§7) — a follow-up once bronze + silver are flowing.

## Cross-references

ADR-0001 (cloud keeps webhooks; local owns scheduled bulk) · ADR-0005 (source catalog & table
naming; fail-loud-on-missing-table) · ADR-0006 (IT Glue hub — **skipped** for pure communication) ·
ADR-0007 (installed module; machine config in `%ProgramData%\Imperion\`) · ADR-0018 (per-client
onboarding-app read-only Graph access — the auth path reused here) · ADR-0021 (the sibling logistics
domain of epic #194 — same ADR-+-collectors-ship-together framing since the FE migration is applied)
· frontend ADR-0042 (four-repo split — bulk off Azure compute) · frontend ADR-0017 (schema
ownership; `0120` defines `m365_email`/`m365_teams`) · frontend ADR-0086 (OKF semantic layer — silver
`interaction` wiring is a future front-end proposal, not authored here). Issues: **#194** (epic —
source-catalog expansion, split by domain), **#199** (this child — **interaction capture: scoped
allowlisted-principal ↔ client; ADR + collectors ship together; CLOSES at merge**), **#198 / #197 /
#196 / #195** (sibling domains).
