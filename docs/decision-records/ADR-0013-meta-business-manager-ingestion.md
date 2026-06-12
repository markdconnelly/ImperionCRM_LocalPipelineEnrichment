# ADR-0013: Meta Business Manager ingestion — system-user token, SecretStore custody, local merge ownership

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-12 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | frontend migration 0075 (#253) · frontend ADR-0042 (four-repo contract) · this repo's ADR-0010 (posture-merge precedent), ADR-0002 (SecretStore custody) |

## Problem

Imperion's organic social presence (Facebook Page + linked Instagram business account)
is invisible to the CRM: posts, comments, page-inbox DMs, and audience metrics live
only in Meta Business Suite. DM senders are real inbound leads that today nobody
captures. The system needs this data in bronze → silver (interaction timeline, lead
capture, social metrics) without adding an AI-visible secret to the cloud or a new
inbound network surface.

## Context

- Frontend migration 0075 (just merged) defines the six bronze tables
  (`facebook_posts`, `facebook_comments`, `facebook_messages`, `instagram_media`,
  `instagram_comments`, `meta_insights`), the `social_metric` silver table, the
  `instagram` interaction source, the `facebook_dm` lead-hook kind, and the widened
  local-pipeline grants (interaction / lead_hook / lead_capture_event / contact /
  contact_social_identity INSERT).
- ADR-0042 (frontend): this repo owns scheduled bulk ingestion; the cloud pipeline
  owns inbound webhooks. Organic social is poll-friendly and slow-moving — no
  webhook need.
- These are Imperion's OWN assets (first-party), so no GDAP/per-client dimension;
  `tenant_id` is the partner tenant.
- Meta auth options: short-lived user tokens (expire, need refresh dance), page
  tokens derived from user tokens (expire with them), or a **Business Manager
  system-user token** (non-expiring, asset-scoped, made for server-to-server).

## Options considered

1. **BM system-user token, SecretStore custody, collect + merge here (CHOSEN).**
   Non-expiring token fits unattended scheduled tasks; the on-prem cert-unlocked
   SecretStore (ADR-0002) is the strongest custody we have for a non-rotating
   credential; the posture-merge precedent (ADR-0010) already establishes this repo
   writing silver in bulk.
2. **Per-user OAuth via the backend's connections flow (frontend ADR-0024).** Wrong
   shape: that flow is for employees' personal accounts; page/IG assets belong to the
   business, tokens expire, and the heavy backfill work would land on Azure compute.
3. **Cloud pipeline collects via webhooks.** Meta webhooks (messenger/feed) are
   real-time complements, not a bulk backfill; standing up a public verified endpoint
   + app review for messaging webhooks is heavy. May be revisited as a future ADR for
   sub-minute DM reaction; bulk polling stays here regardless (ADR-0042 boundary).
4. **Key Vault custody with SecretStore mirror (the KQM pattern).** Rejected: the
   token is non-expiring and grants messaging read — putting a copy in the cloud
   widens the blast radius for zero operational gain (only this node consumes it).
   Hence Resolve-ImperionMetaToken has deliberately NO Key Vault fallback.

## Decision

- **Auth:** BM system-user token with scopes `pages_show_list`,
  `pages_read_engagement`, `pages_read_user_content`, `pages_messaging`,
  `pages_manage_metadata`, `read_insights`, `instagram_basic`,
  `instagram_manage_insights`, `business_management`. SecretStore secret
  `meta-system-user-token` (config key `MetaSystemUserToken`); explicit `-Token`
  override for ad-hoc runs; **no Key Vault fallback**. Bearer-header transport only;
  `paging.next`'s embedded `access_token` is stripped before following. The page-token
  hop (`Get-ImperionMetaPageToken`) is fetched per run and never persisted.
- **Collection:** connect/get/post spine under `Public/meta/` — posts, post comments,
  page-inbox messages (one bronze row per message), IG media, IG comments, Page + IG
  insights (metrics requested one at a time so deprecations degrade to warnings).
  Sources stamped `facebook` / `instagram` / `meta` per the 0075 comment contract.
- **Merge ownership is LOCAL** (`Invoke-ImperionMetaMerge`, posture-merge precedent):
  bronze → `interaction` (social_post / social_comment / dm), DM senders →
  `lead_hook('facebook_dm')` + minimal `contact` + `contact_social_identity` + ONE
  `lead_capture_event` per sender; commenters stay timeline-only; `meta_insights` →
  `social_metric`. All steps set-based and idempotent (NOT EXISTS / ON CONFLICT DO
  NOTHING), INSERT-only on silver.
- **Tasks:** `meta/social` + `meta/insights`, daily, gated (page id env var + token +
  0075 applied); registration deferred to server bringup (#102).

## Consequences

### Security impact

A non-expiring token that can read the page inbox now exists — custody is the
on-prem SecretStore only, unlocked by the machine cert (ADR-0002); it never appears
in logs, URLs, the repo, or the cloud. DM bronze rows carry PII (names, message
text): covered by the standard bronze posture (no row-content logging, web-role read
gated by 0075 grants). The local-pipeline DB role gains the 0075 silver INSERT grants
— a widening recorded by the frontend migration and exercised only by the
NOT-EXISTS-gated merge. Token rotation = regenerate in Business Suite + `Set-Secret`;
document in the secret-rotation runbook.

### Cost impact

None beyond negligible API calls (free) and local compute. No new Azure resources;
no AI spend.

### Operational impact

Two new daily tasks in the standard gated shape; one new secret to provision; the
page id surfaces as `IMPERION_META_PAGE_ID`. Meta deprecates insight metrics
regularly — expect occasional warnings and trim metric lists; field maps need a
verify-live pass on first run (docs/integrations/meta.md).

## Future considerations

- Real-time DM capture via Meta webhooks in the cloud pipeline (new ADR there) if
  daily lead latency proves too slow.
- Post/media-level insights (per-entity metrics) once entity-level reporting is
  wanted; `meta_insights.entity_kind` already accommodates `post`/`media`.
- Paid-campaign data stays in the existing campaign tables (frontend ADR-0012);
  `social_metric` is organic-only.

## Cross-references

frontend migration `db/migrations/0075_meta_business_bronze.sql` · frontend ADR-0042
· this repo's ADR-0002 (cert-rooted SecretStore), ADR-0005 (source catalog),
ADR-0010 (local silver merge precedent) · `docs/integrations/meta.md`.
