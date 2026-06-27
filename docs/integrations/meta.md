# Meta Business Manager (Facebook Page + Instagram) — organic social ingestion

_ImperionCRM_LocalPipelineEnrichment — `docs/integrations`_ · issue #126 · IG DMs #361 ·
Social Engagement + post/ad metrics (slice H) #357 · ADR-0013 · ADR-0124 ·
front-end migrations 0075 + 0206 + 0210

Imperion's own Business Suite assets — the Facebook Page and the linked Instagram
business account — are first-party marketing surfaces (NOT client data). This source
collects organic posts, comments, page-inbox (Messenger) DMs, IG media/comments,
**Instagram Direct Messages**, and daily insight snapshots into the 0075 / 0207 bronze
tables, then merges them to silver locally (`Invoke-ImperionMetaMerge`, the posture-merge
precedent). IG DMs are the READ half of the IG messaging use case (front-end ADR-0124
Social Media plane; the outbound IG reply ships in ImperionCRM_Backend #419).

## Auth model

- **Business Manager SYSTEM-USER token** (non-expiring) created in Meta Business
  Suite → Business settings → System users. Generate the token with the scopes below
  and assign the Page + IG asset to the system user.
- **Scopes:** `pages_show_list`, `pages_read_engagement`, `pages_read_user_content`,
  `pages_messaging`, `pages_manage_metadata`, `read_insights`, `instagram_basic`,
  `instagram_manage_insights`, `business_management`, (IG DMs, #361)
  `instagram_manage_messages`, and (Lead Ads, #362) `leads_retrieval`. The IG-messaging
  scope is **still in Meta App Review** — IG DM collection is dormant/fail-closed until it
  is approved and `conn-company-meta` is seeded (same gate as the outbound reply,
  ImperionCRM_Backend #419). The **Lead Ads** track additionally needs `leads_retrieval`
  on the page token (see the Lead Ads section below).
- **Custody (the KQM pattern, ADR-0013):** `Resolve-ImperionMetaToken` resolves
  explicit `-Token` → SecretStore mirror `meta-system-user-token` (config key
  `MetaSystemUserToken`) → Key Vault original `Meta-SystemUser-Token` (config key
  `MetaTokenVaultSecret`, read by the cert SP). The Key Vault original is the interim
  path until the server's SecretStore bootstrap (#102) mirrors it on-prem
  (`Set-Secret -Name meta-system-user-token -Vault <vault>`); after mirroring, the
  Key Vault copy may be deleted to narrow custody of this non-expiring token.
- **Transport:** the token rides the `Authorization: Bearer` header — never the
  querystring. Meta's `paging.next` URLs embed `access_token=`; the connect layer
  (`Invoke-ImperionMetaRequest`) strips it before following, so no secret-bearing URL
  is ever held or logged.
- **Page token hop:** `/conversations` (the page inbox) rejects the system-user token
  and needs a **page access token** — `Get-ImperionMetaPageToken -PageId <id>` fetches
  it per run (`GET /{page-id}?fields=access_token`); it is never persisted or logged.
  `Get-ImperionMetaPageToken -Discover` lists pages via `/me/accounts` to find the
  page id during bootstrap.

## Data collected (Graph API v23.0)

| Cmdlet | Edge | Bronze table | source |
| --- | --- | --- | --- |
| `Get-ImperionMetaPagePost` | `/{page-id}/posts` (+ shares/comments/reactions summaries) | `facebook_posts` | `facebook` |
| `Get-ImperionMetaPostComment` | `/{post-id}/comments` | `facebook_comments` | `facebook` |
| `Get-ImperionMetaConversation` | `/{page-id}/conversations` + nested messages (PAGE token) | `facebook_messages` (one row per **message**) | `facebook` |
| `Get-ImperionInstagramMedia` | `/{page-id}?fields=instagram_business_account` → `/{ig-user-id}/media` | `instagram_media` | `instagram` |
| `Get-ImperionInstagramComment` | `/{media-id}/comments` | `instagram_comments` | `instagram` |
| `Get-ImperionInstagramMessage` | `/{page-id}/conversations?platform=instagram` + nested messages (PAGE token) | `instagram_messages` (one row per **message**, 0206) | `instagram` |
| `Get-ImperionMetaInsight` | `/{page-id}/insights`, `/{ig-user-id}/insights`, `/{ig-user-id}?fields=followers_count` | `meta_insights` (external_id `<entity_kind>:<entity_id>:<metric>:<period>:<end_time>`) | `meta` |

Writers: `Set-ImperionMetaPostToBronze`, `Set-ImperionMetaCommentToBronze`,
`Set-ImperionMetaMessageToBronze`, `Set-ImperionInstagramMediaToBronze`,
`Set-ImperionInstagramCommentToBronze`, `Set-ImperionInstagramMessageToBronze`,
`Set-ImperionMetaInsightToBronze` — all thin
adapters over `Invoke-ImperionBronzePost` with the exact 0075 / 0207 column sets
(change-detected upsert on `(tenant_id, source, external_id)`).

## Silver merge (local ownership)

`Invoke-ImperionMetaMerge` — idempotent set-based steps (NOT EXISTS /
ON CONFLICT DO NOTHING; INSERT-only, never UPDATE/DELETE on silver):

1–4. Posts/comments/media/DMs → `interaction` (kinds `social_post` /
`social_comment` / `dm`; FB posts and IG media are outbound, comments inbound, FB DM
direction by `from_id = page_id`, IG DM direction by `from_id = ig_user_id`).
5. **DM senders become leads** (the 0075 / 0207 contract; commenters stay
timeline-only), per channel: one `lead_hook` for the FB page inbox (kind `facebook_dm`,
"Facebook page inbox") and one for the IG inbox (kind `instagram_dm`, "Instagram direct
messages"); a minimal `contact` + `contact_social_identity` (platform `facebook` /
`instagram`) per unknown sender; and ONE `lead_capture_event` per sender keyed on
`payload_bronze->>'from_id'`.
6. `meta_insights` → `social_metric` (platform `facebook` for `entity_kind='page'`,
else `instagram`; guarded numeric/timestamptz casts).
7–8. **DMs with an onboarded client → `client_communication` (`social_dm`)** — the SECOND,
FILTERED projection of the same DM bronze (#383, front-end #1370 /
`docs/database/social-dm-foldin.md`; silver `client_communication` 0211, ADR-0126),
alongside step 4's unfiltered `interaction` timeline. `facebook_messages` →
`source_system=meta_messenger`, `instagram_messages` → `source_system=instagram_dm`. A DM
is retained **iff** its non-Imperion counterparty resolves to a **linked client contact**
via `contact_social_identity` (an INNER JOIN LATERAL — the filter gate; **no `account_domain`
path**, handles have no email domain). Stamps `account_id` (+ `contact_id`). PII-minimal:
`subject` NULL, `snippet` = truncated message preview (**never the full body**, ADR-0126
privacy), `data_class=client_pii`; `direction` by sender (inbound = client→Imperion).
Idempotent **upsert** on `(channel, source_system, external_id)` with `content_hash` change
detection — so unlike steps 1–6 this step DOES `UPDATE` (a content-changed re-merge refreshes
the row). Unlinked-handle DMs stay `interaction` / `lead_capture_event` only (step 5).

## Lead Ads (separate track — `leads_retrieval`, LP #362 / front-end migration 0207)

A **separate track** from the organic ingestion above (and from the Meta Marketing push,
front-end #406): the App Review use case **"capture & manage ad leads"** / permission
**`leads_retrieval`**. Facebook/Instagram instant-form leads are pulled from the company
Page and merged to the lead pipeline as capture-inbox leads (front-end ADR-0124 decision 6;
`source = meta_lead_ad`).

- **Auth:** the **page access token** (`Get-ImperionMetaPageToken`) must additionally carry
  `leads_retrieval`. Same bearer-header transport + paging-token stripping as the organic
  track. No new credential — `conn-company-meta`.
- **Collectors (Graph v23.0):**

  | Cmdlet | Edge | Bronze table | source |
  | --- | --- | --- | --- |
  | `Get-ImperionMetaLeadForm` | `/{page-id}/leadgen_forms` | `meta_lead_ad_forms` (form metadata, no PII) | `meta_lead_ad` |
  | `Get-ImperionMetaLead` | `/{form-id}/leads` (fanned per form) | `meta_lead_ads` (one row per submitted lead) | `meta_lead_ad` |

  Writers `Set-ImperionMetaLeadFormToBronze` / `Set-ImperionMetaLeadToBronze` — thin
  adapters over `Invoke-ImperionBronzePost` with the exact 0207 column sets. `field_data`
  answers are **PII-adjacent — never logged** (counts/ids only, ADR-0086); the convenience
  flat columns `full_name`/`email`/`phone_number` are extracted from `field_data` while the
  full answer array is kept as JSON + in `raw_payload`.
- **Silver merge (local ownership, ADR-0026):** `Invoke-ImperionMetaLeadAdsMerge` — three
  idempotent set-based steps (NOT EXISTS; INSERT-only):
  1. ONE `lead_hook` (kind `facebook_lead`, "Facebook Lead Ads"), `config` stamping
     `source=meta_lead_ad` + the page id.
  2. A minimal `contact` + `contact_social_identity` (platform `facebook`) per unknown
     submitter, identity key = the submitter's email when present (stable across forms),
     else `leadgen:<leadgen_id>`.
  3. ONE `lead_capture_event` per submitted lead, **idempotent on the Meta leadgen id**
     (`payload_bronze->>'leadgen_id'`); payload carries `source=meta_lead_ad`, the leadgen
     id, form/ad/campaign ids, and the field-data answers.
- **Real-time path (future):** leadgen webhooks could front this via the cloud Pipeline
  (APIM callback ingress); the baseline here is the scheduled poll (poll-first, ADR-0124 #8).

## Social Engagement + Social Metric (slice H — #357 / front-end Social plane epic #1338, ADR-0124)

Slice H lands two NEW silver surfaces from the Meta source — the inbound **Social Engagement**
store and normalized **Social Metric** time-series — plus the **post** and **ad** metric
collectors that feed them. Poll-first (no webhooks v1, ADR-0124 #8); merge co-locates with
ingestion (ADR-0026). The comment + metric halves reuse the 0075 bronze tables; **brand
mentions** add ONE new bronze table, `meta_mentions` (front-end #1365).

### Social Engagement (comments + mentions → silver `social_engagement`, migration 0210)

`Invoke-ImperionSocialEngagementSync` collects FB post comments + IG media comments into the
existing `facebook_comments` / `instagram_comments` bronze **and brand mentions into the new
`meta_mentions` bronze**, then `Invoke-ImperionSocialEngagementMerge` merges all three to silver
**`social_engagement`** (ADR-0124 #2 inbound split — the store that keeps public chatter OFF the
contact-centric Interaction timeline). Three idempotent steps, each
`ON CONFLICT (channel, external_id) DO NOTHING`:

| Bronze | → silver `social_engagement` | channel | kind |
| --- | --- | --- | --- |
| `facebook_comments` | one row per comment | `facebook` | `comment` |
| `instagram_comments` | one row per comment | `instagram` | `comment` |
| `meta_mentions` | one row per brand mention | `facebook` / `instagram` (= `platform`) | `mention` |

The merge lands ONLY the ingestion-owned columns: `channel`, `external_id`, `kind`, `body`,
`posted_at`, the `author_*` fields (third-party PII — OKF lawful-basis note, ADR-0025), and
`source_url`. It leaves `contact_id` / `intent` / `assigned_agent_key` NULL and `status` at its
`'new'` default — **slice G** (contact-link on match) and triage set those. INSERT-only.

#### Brand mentions (FB `/tagged` + IG `/tags` → bronze `meta_mentions`) — LP #391 / front-end #1365

The MENTIONS half of the inbound split, now that the `meta_mentions` bronze table exists
(front-end migration; this repo authors no migration, system CLAUDE.md §1).
`Get-ImperionMetaMention` polls two edges, **fail-soft per-network** (one network's error never
aborts the other, §1):

| Edge | Meaning | `platform` | `mention_kind` |
| --- | --- | --- | --- |
| `GET /{page-id}/tagged` | posts our Page is tagged in | `facebook` | `tagged_post` |
| `GET /{ig-user-id}/tags` | media our IG account is tagged in (IG user resolved from the linked Page) | `instagram` | `tagged_media` |

`Set-ImperionMetaMentionToBronze` upserts into `meta_mentions` **`ON CONFLICT (platform,
mention_id)`** (idempotent replace-from-source, no `content_hash` → `-NoChangeDetect`). The
table is NOT the standard bronze envelope: its columns are `platform`, `mention_id`,
`mention_kind`, `permalink`, `message`, `author_id`, `author_username`, `author_name`,
`created_time`, `raw` (jsonb), plus DB-default `id` / `ingested_at`. The merge step maps
`platform`→`channel`, `mention_id`→`external_id`, `message`→`body`, `created_time`→`posted_at`,
`author_id/username/name`→`author_external_id/handle/display_name`, and `permalink`→`source_url`
(the mention lives on someone else's content, so `on_social_post_channel_id` stays NULL).

Both comment and mention collection run in ONE `Invoke-ImperionSocialEngagementSync` pass — the
existing `Imperion-SocialEngagementSync` scheduled task, **no new task** (dormant until Mark's
host `Register-ImperionTask`).

> **GRANT GAP (verify before prod).** LP connects as the Postgres role
> **`imperion-localpipeline`** (config `Db.Username`). Two grants are front-end-owned prereqs
> (schema/grants are front-end-owned, system CLAUDE.md §1 — no migration authored here):
> (1) `social_engagement` RW — migration 0210 granted it to `mgid-imperioncrmpipeline`, NOT to
> `imperion-localpipeline`; the LP grant lands in **front-end migration 0212** (PR #1385, merged,
> awaits Mark prod-apply). (2) `meta_mentions` RW to `imperion-localpipeline` — in the front-end
> agent's migration alongside the table (front-end #1365). Until both apply, the prod writes FAIL
> CLOSED and the next run converges. `social_metric` already grants LP write (0075), unaffected.

### Social Metric (post + ad insights → silver `social_metric`, NORMALIZED names — resolves #135)

`Invoke-ImperionSocialMetricSync` collects per-post + per-media insights (and, when an ad account
is configured, paid ad + campaign insights) into the existing `meta_insights` bronze, then
`Invoke-ImperionSocialMetricMerge` merges them to silver **`social_metric`** with the metric names
**normalized** at silver. This resolves front-end issue **#135** (raw Meta metric names are
unstable across networks and API versions): bronze stays lossless (raw name preserved), silver
carries ONE canonical, network-agnostic vocabulary.

| Cmdlet | Edge | entity_kind | Bronze table |
| --- | --- | --- | --- |
| `Get-ImperionMetaPostInsight` | `/{post-id}/insights`, `/{media-id}/insights` | `post`, `media` | `meta_insights` |
| `Get-ImperionMetaAdInsight` | `/act_{ad-account-id}/insights?level={campaign\|ad}` | `campaign`, `ad` | `meta_insights` |

The merge derives `social_metric.platform` from `entity_kind` (`page`/`post` → `facebook`;
`ig_user`/`media` → `instagram`; `ad`/`campaign`/`adset`/`adaccount` → `meta_ads`) and is
`ON CONFLICT (platform, entity_kind, entity_external_id, metric, period, captured_at) DO NOTHING`.
The ad half is **optional** — with no `IMPERION_META_AD_ACCOUNT_ID` the ad collector returns
nothing and the run proceeds with organic post/media metrics only (a Page with no spend never
breaks the task). Spend/amount values are never logged (counts/ids only).

**Canonical metric vocabulary (#135)** — the single source of truth is the module-internal
`Get-ImperionSocialMetricCanonSql` (a SQL `CASE` applied in the merge); an un-mapped raw name
passes through lower-cased (never dropped). Current mappings:

| canonical | raw Meta names collapsed onto it |
| --- | --- |
| `impressions` | `page_impressions`, `page_impressions_unique`, `impressions`, `post_impressions`, `post_impressions_unique` |
| `reach` | `page_reach`, `reach`, `page_impressions_organic_unique` |
| `engagement` | `page_post_engagements`, `post_engagements`, `post_clicks`, `accounts_engaged`, `total_interactions` |
| `profile_views` | `profile_views`, `page_views_total` |
| `follower_count` | `followers_count`, `page_fans`, `follower_count` |
| `video_views` | `post_video_views`, `video_views`, `plays` |
| `saved` | `saved` |
| `shares` | `shares`, `post_shares` |
| `comments` | `comments`, `post_comments` |
| `spend` | `spend` (paid) |
| `clicks` | `clicks`, `inline_link_clicks` (paid) |
| `ctr` / `cpc` / `cpm` / `frequency` | `ctr` / `cpc` / `cpm` / `frequency` (paid) |

> The existing `Invoke-ImperionMetaMerge` step 6 (`meta_insights → social_metric`, #126) keeps
> its passthrough mapping for the page/ig organic snapshots it already owns; slice H's new
> post/ad collectors merge through `Invoke-ImperionSocialMetricMerge` so the normalized
> vocabulary applies to the slice-H entity kinds. A future tidy-up may route all
> `meta_insights → social_metric` through the normalized merge (tracked in the PR).

### Slice-H tasks

| Task (cmdlet) | Entities | Cadence |
| --- | --- | --- |
| `Imperion-MetaEngagement` (`Invoke-ImperionSocialEngagementSync`) | FB/IG post comments → `social_engagement` | Daily |
| `Imperion-MetaMetrics` (`Invoke-ImperionSocialMetricSync`) | post + media + ad/campaign insights → `social_metric` (normalized) | Daily |

Both are **gated** (missing `IMPERION_META_PAGE_ID` / unprovisioned token / unapplied
0075/0210 → log + exit cleanly) and **dormant until registration** (Mark runs
`Register-ImperionTask` on the host — admin-gated, server bringup #102). Promoted to `*Sync`
cmdlets per ADR-0007 (epic #286); no loose `.task.ps1` entry script.

## Rate limits & retry

Meta applies per-app + per-page Platform Rate Limits (sliding-window, headers
`X-App-Usage` / `X-Business-Use-Case-Usage`); 429/`Retry-After` throttling is handled
by `Invoke-ImperionRestWithRetry`. Daily cadence at our volumes is far inside budget.
**Insight metrics deprecate often**: `Get-ImperionMetaInsight` requests metrics ONE AT
A TIME, so a dead metric (#100 error) logs a warning and the run continues — trim
retired names from `-PageMetric`/`-IgMetric` as Meta retires them.

### Verified metric defaults (after the first live run #132/#133, fixed in #135)

- **Page (`-PageMetric`)** = `page_impressions_unique`, `page_post_engagements`,
  `page_views_total`. **Dropped as deprecated:** `page_impressions` and `page_fans`
  (both #100 on this page).
- **IG time-series (`-IgMetric`)** = empty by default. `reach` was removed — it returns
  a since-window #100 complaint on the paged call; re-add only with a verified window.
- **IG total-value (`-IgTotalValueMetric`)** = `profile_views`, `accounts_engaged`.
  These metrics now **require `metric_type=total_value`** and return a single
  `{total_value:{value}}` aggregate (no `values[]` series); the collector requests them
  with that parameter and dates the single point to today (UTC) for one idempotent row
  per day.
- **API version is pinned** to `v23.0` end to end. Meta rewrites the version segment in
  the `paging.next` URL it returns (observed `v23.0` -> `v25.0`); `Invoke-ImperionMetaRequest`
  re-pins the followed URL's `/vNN.N/` path segment back to the pin so a multi-page call
  never silently drifts onto an untested version (#135).

## Cadence & tasks

| Task | Entities | Cadence |
| --- | --- | --- |
| `meta/social.task.ps1` | posts, comments, DMs, IG media/comments + merge | Daily |
| `meta/insights.task.ps1` | Page + IG insight snapshots + merge | Daily |
| `Imperion-MetaLeadAds` (`Invoke-ImperionMetaLeadAdsSync`) | Lead Ad forms + submitted leads + merge | Daily @ 04:08 |
| `meta/engagement.task.ps1` (`Invoke-ImperionSocialEngagementSync`) | FB/IG post comments → `social_engagement` + merge (slice H #357) | Daily |
| `meta/metrics.task.ps1` (`Invoke-ImperionSocialMetricSync`) | post + media + ad/campaign insights → normalized `social_metric` + merge (slice H #357 / #135) | Daily |

All are **gated**: missing `IMPERION_META_PAGE_ID`, an unprovisioned token (for Lead Ads,
one lacking `leads_retrieval`), or a not-yet-applied migration (0075 / 0207) logs a warning
and exits cleanly. Task **registration is deferred to server bringup (#102)**.

### Manual run path

```powershell
Import-Module ImperionPipeline
Initialize-ImperionContext

# Bootstrap: find the page id (page_token is a secret - do not log the output)
Get-ImperionMetaPageToken -Discover | Select-Object page_id, page_name

$env:IMPERION_META_PAGE_ID = '<page-id>'
& "<repo>\scheduled-tasks\meta\social.task.ps1"
& "<repo>\scheduled-tasks\meta\insights.task.ps1"

# Slice H (#357) — promoted *Sync cmdlets (no entry script):
Invoke-ImperionSocialEngagementSync          # FB/IG comments → social_engagement
$env:IMPERION_META_AD_ACCOUNT_ID = '<act_id>'  # optional: enables the paid ad/campaign half
Invoke-ImperionSocialMetricSync              # post + ad insights → normalized social_metric
```

## Field assumptions — VERIFY LIVE

The flat-column field maps follow Meta's v23.0 published references, but Meta prunes
fields silently by permission tier and version. Unreadable fields land NULL in the
flat columns and survive losslessly in `raw_payload` — **verify the flat columns
against the first live run before trusting them** (the `Get-ImperionKqmOpportunity`
precedent). Known tolerances: IG comment `from` is permission-gated (username still
identifies the commenter); `shares.count` is absent on share-disabled posts.

## Provenance & PII

`tenant_id` = Imperion's own tenant (first-party assets). DM payloads carry message
text and sender names — **never log row contents**; bronze custody only, lead capture
is the only silver surface that carries the sender forward. Having a sender's DM is
NOT consent to contact (the system-wide lawful-basis guardrail).
