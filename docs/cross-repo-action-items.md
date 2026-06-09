# Cross-repo action items

What the **sibling repos** need to do so the data this local pipeline lands actually reaches the
front-end AI agents (the goal in `CLAUDE.md` §1: capture *all* company knowledge → agent-aware).
Maintained here as the cross-repo checklist (`CLAUDE.md` §9). ADR numbers are **per-repo**.

Status of this repo (the producer): bronze **get + post** layers built and unit-green; schema
(`0038`–`0043`) live; least-privilege SP role + grants (`0044`) applied and the
cert→token→Postgres write chain proven. So bronze rows *can* flow today; the items below carry
them onward to silver/gold/vectors and prevent double-ingestion.

---

## `ImperionCRM` (front-end — owns schema, migrations, silver/gold merge)

1. **Silver/gold merge must incorporate the new bronze entities** this repo writes, or the agent
   stays blind to them. New since the per-source bronze work:
   - `autotask_contracts`, `autotask_tickets` (CRM/support)
   - `televy_reports`, `darkwebid_exposures` → silver `credential_exposure` / `assessment_artifact`
     (the `0043` silver tables exist; confirm the merge actually folds bronze → silver → gold)
   - the **security-posture** set (`secure_scores`, the policy bronze, the `*_golden` baselines) and
     **drift** output — decide how posture/drift surfaces to the agent (gold summary? dedicated view?)
   - the **IT Glue export graph** (`itglue_export_*` + `itglue_export_relationship`) — how (if at all)
     it feeds gold/knowledge objects.
   **Action:** extend the silver/gold merge + add gold summaries/knowledge objects for these entities.
2. **Vector lifecycle contract** (§7): the embedding **model + dimension + chunking_version** the
   agent queries must be pinned and shared. This repo does the embedding but writes into the
   front-end-owned vector table — confirm the table/columns + the pinned model in
   `docs/database/` before the vectorization stage runs.
3. **Future bronze tables need grants too:** any new `{source}_{entity}` bronze added by a later
   migration must be added to `0044`'s grant list (or a follow-on grant migration) so
   `imperion-localpipeline` can write it. Tables still to come (handoff §3): `m365_devices`,
   `itglue_devices`, `website_*`, apollo, and confirmed `kqm_proposals`/`docusign_contracts` shapes.

## `ImperionCRM_Pipeline` (cloud Functions — webhooks + low-latency only)

4. **Scope cloud polling down to GUI-refresh / webhooks** so it doesn't double-ingest what this
   repo now owns in bulk (front-end ADR-0040 noted this). Specifically retire/limit the cloud
   **Dark Web ID + Televy** bulk timers and any bulk source polling; keep **inbound webhooks**
   (Autotask tickets, Graph change-notifications + renewal) and sub-minute reactions (`CLAUDE.md` §1).
5. **`autotask_tickets` shared-write coordination:** cloud webhooks write tickets in real time;
   this repo bulk-reconciles the same table. Keys align (`tenant_id, source, external_id`) so upserts
   are safe, but confirm both sides use the **same external_id + content_hash** semantics so neither
   thrashes the other's rows. (`autotask_contracts` already had rows in prod — confirm who owns the
   authoritative write.)

## `ImperionCRM_Backend` (Azure Functions — agent + semantic search)

6. **Agent/semantic search consumes the new gold + vectors** once items 1–2 land: ensure the
   orchestrator's retrieval covers the new knowledge objects and queries the **same vector space**
   (model/dimension) this repo embeds into. Downstream of front-end gold + this repo's vectorization.

---

## Suggested sequence
items **1 → 2** (front-end: silver/gold + vector contract) unblock this repo's gold + vectorization
stage; **4 → 5** (cloud: stop double-ingest) should land alongside this repo's tasks going live;
**6** (backend) is last, once gold/vectors exist. Open a tracking issue/ADR in each named repo.
