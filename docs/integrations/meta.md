# Meta Business Manager (Facebook Page + Instagram) — organic social ingestion

_ImperionCRM_LocalPipelineEnrichment — `docs/integrations`_ · issue #126 · IG DMs #361 ·
ADR-0013 · front-end migrations 0075 + 0206

Imperion's own Business Suite assets — the Facebook Page and the linked Instagram
business account — are first-party marketing surfaces (NOT client data). This source
collects organic posts, comments, page-inbox (Messenger) DMs, IG media/comments,
**Instagram Direct Messages**, and daily insight snapshots into the 0075 / 0206 bronze
tables, then merges them to silver locally (`Invoke-ImperionMetaMerge`, the posture-merge
precedent). IG DMs are the READ half of the IG messaging use case (front-end ADR-0124
Social Media plane; the outbound IG reply ships in ImperionCRM_Backend #419).

## Auth model

- **Business Manager SYSTEM-USER token** (non-expiring) created in Meta Business
  Suite → Business settings → System users. Generate the token with the scopes below
  and assign the Page + IG asset to the system user.
- **Scopes:** `pages_show_list`, `pages_read_engagement`, `pages_read_user_content`,
  `pages_messaging`, `pages_manage_metadata`, `read_insights`, `instagram_basic`,
  `instagram_manage_insights`, `business_management`, and (IG DMs, #361)
  `instagram_manage_messages`. The IG-messaging scope is **still in Meta App Review** —
  IG DM collection is dormant/fail-closed until it is approved and `conn-company-meta`
  is seeded (same gate as the outbound reply, ImperionCRM_Backend #419).
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
adapters over `Invoke-ImperionBronzePost` with the exact 0075 / 0206 column sets
(change-detected upsert on `(tenant_id, source, external_id)`).

## Silver merge (local ownership)

`Invoke-ImperionMetaMerge` — idempotent set-based steps (NOT EXISTS /
ON CONFLICT DO NOTHING; INSERT-only, never UPDATE/DELETE on silver):

1–4. Posts/comments/media/DMs → `interaction` (kinds `social_post` /
`social_comment` / `dm`; FB posts and IG media are outbound, comments inbound, FB DM
direction by `from_id = page_id`, IG DM direction by `from_id = ig_user_id`).
5. **DM senders become leads** (the 0075 / 0206 contract; commenters stay
timeline-only), per channel: one `lead_hook` for the FB page inbox (kind `facebook_dm`,
"Facebook page inbox") and one for the IG inbox (kind `instagram_dm`, "Instagram direct
messages"); a minimal `contact` + `contact_social_identity` (platform `facebook` /
`instagram`) per unknown sender; and ONE `lead_capture_event` per sender keyed on
`payload_bronze->>'from_id'`.
6. `meta_insights` → `social_metric` (platform `facebook` for `entity_kind='page'`,
else `instagram`; guarded numeric/timestamptz casts).

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

Both are **gated**: missing `IMPERION_META_PAGE_ID`, an unprovisioned token, or a
not-yet-applied 0075 logs a warning and exits cleanly. Task **registration is
deferred to server bringup (#102)**.

### Manual run path

```powershell
Import-Module ImperionPipeline
Initialize-ImperionContext

# Bootstrap: find the page id (page_token is a secret - do not log the output)
Get-ImperionMetaPageToken -Discover | Select-Object page_id, page_name

$env:IMPERION_META_PAGE_ID = '<page-id>'
& "<repo>\scheduled-tasks\meta\social.task.ps1"
& "<repo>\scheduled-tasks\meta\insights.task.ps1"
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
