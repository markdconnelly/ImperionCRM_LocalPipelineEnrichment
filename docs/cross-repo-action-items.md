# Cross-repo action items

What the **sibling repos** need to do so the data this local pipeline lands actually reaches the
front-end AI agents (the goal in `CLAUDE.md` §1: capture *all* company knowledge → agent-aware).
Maintained here as the cross-repo checklist (`CLAUDE.md` §9). ADR numbers are **per-repo**.

Status of this repo (the producer): the full bronze→silver→gold→vectors spine is built and
**gold + vectorization is LIVE in prod** (~205 `knowledge_object` rows embedded nightly); LP now
owns the bronze→silver **merge** for every source it bulk-ingests (ADR-0026). So the items below
are largely **superseded** — see the reconciliation first.

---

## Reconciliation (2026-06-29) — most of the original checklist is now closed

The doc below was written when silver/gold merge for LP-ingested sources still lived in the
cloud Pipeline and was framed as a front-end ask. **ADR-0026 moved that ownership to LP**, and
the cloud cedes have shipped. Current state:

- **Item 1 (silver/gold for new bronze) — LP-OWNED now, not a front-end ask.** Per ADR-0026 LP
  runs the merge for the sources it ingests: posture / Meta / DNS (precedent) + M365 directory,
  `cloud_asset`, UniFi `device`, Pax8 `license_assignment`, `software_ci`, the Social plane
  (`social_engagement` / `social_metric` / Threads / Meta lead-ads `lead_hook`), and the
  client-filtered `client_communication` ledger. The front end still owns the *schema + OKF
  meaning*; gold composers cover account/contact/contract/ticket/device/exposure/assessment/
  proposal/posture/social/conversation_segment/memory/semantic_concept. See
  [`collector-inventory.md`](collector-inventory.md).
- **Item 2 (vector contract pinned + shared) — DONE.** The contract is consumed from the front
  end's one machine-readable home (`db/contracts/vector-contract.json`, front-end ADR-0102) via
  `Get-ImperionVectorContract` (ADR-0025); `voyage-3-large` @ 1024 (front-end migration 0045 /
  ADR-0041). The Voyage key reads Key Vault `conn-platform-voyage` (#407).
- **Item 4 (scope cloud polling down) — DONE.** The cloud Pipeline's bulk-poll timers are RETIRED
  (CLAUDE.md §1 / pipeline ADR-0011); it keeps inbound webhooks + the live/webhook-driven merge
  only. The cedes landed: M365 directory merge (Pipeline #157 / #134, 2026-06-22) and `cloud_asset`
  merge (Pipeline #135 / #138, 2026-06-19).
- **Item 6 (backend consumes gold + vectors) — substantially landed.** Gold + vectors are LIVE;
  the backend embeds only queries against the same pinned contract (backend ADR-0034).
- **Still open:** Item 3 (every NEW `{source}_{entity}` bronze needs a front-end grant on the LP
  Postgres role) is a standing per-source checklist, not a one-time task; and Item 5 (`autotask_tickets`
  shared-write coordination) stays live wherever the cloud webhook and the LP bulk reconcile touch
  the same table.

The original checklist is retained below for provenance.

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
