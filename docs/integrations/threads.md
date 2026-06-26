# Threads (graph.threads.net) — organic presence ingestion

_ImperionCRM_LocalPipelineEnrichment — `docs/integrations`_ · LocalPipeline #356 ·
front-end Threads epic ImperionCRM#1334 / ADR-0125 · silver mapping ImperionCRM#1347 ·
front-end migration 0208

Imperion runs its **own** Threads business presence — Belle drafts, humans approve outbound
(epic #1334, Social Media plane ADR-0124). This source (slice **S3 — ingest collectors**)
collects our own **posts**, **replies** on those posts, public **mentions** of us, and
**organic insights** into the 0208 bronze tables, then merges them to silver locally
(`Invoke-ImperionThreadsMerge`, the Meta/posture-merge precedent, ADR-0026). Threads is a
**SEPARATE API** from the FB/IG Meta Graph — `graph.threads.net` with its **own Threads
OAuth long-lived token** — so it shares no token or code with the Meta integration
(`conn-company-meta`, 0075). It is a **net-new connector** (`conn-company-threads`, company
scope) feeding the **existing** unified `interaction` timeline + `social_metric` layer (no
silo, ADR-0125 D2).

## Auth model

- **Long-lived Threads access token** obtained via the Threads OAuth flow (front-end S1
  connector card, ImperionCRM#1335). Company-scope: ONE token covers our presence.
- **App Review — the six scopes (ADR-0125 D4):** `threads_basic`,
  `threads_content_publish`, `threads_manage_replies`, `threads_read_replies`,
  `threads_manage_mentions`, `threads_manage_insights`. They map onto the bronze feeds:
  `threads_basic`+`threads_content_publish` → posts; `threads_manage_replies`+
  `threads_read_replies` → replies; `threads_manage_mentions` → mentions;
  `threads_manage_insights` → insights. (`threads_content_publish` is the outbound-compose
  half — used by Belle's reply path in `ImperionCRM_Backend`, not this read-only collector.)
- **Custody (the UniFi/credential-registry pattern, ADR-0103 / #319):**
  `Resolve-ImperionThreadsToken` resolves explicit `-Token` → else
  `Resolve-ImperionCompanyCredential -Provider 'threads' -Field 'accessToken'` — the
  DB-authoritative `connection` registry → Key Vault path. The GUI writes the token to Key
  Vault under `conn-company-threads` and records the name on the registry row; the cert-backed
  app SP (Key Vault Secrets User) reads it by reference. **No SecretStore mirror, no
  hard-coded vault name.** The token is returned only to the immediate caller and **never
  logged or persisted**.
- **Transport:** the token rides the `Authorization: Bearer` header — never the querystring.
  Threads' `paging.next` URLs embed `access_token=`; the connect layer
  (`Invoke-ImperionThreadsRequest`) strips it before following, so no secret-bearing URL is
  ever held or logged. The leading `/vNN.N/` path segment is re-pinned to the tested version
  on every followed page (the Meta #135 precedent).

## Data collected (Threads API v1.0)

| Cmdlet | Edge | Bronze table | source |
| --- | --- | --- | --- |
| `Get-ImperionThreadsPost` | `/me/threads` | `threads_posts` | `threads` |
| `Get-ImperionThreadsReply` | `/{thread-id}/replies` (fanned per our post) | `threads_replies` | `threads` |
| `Get-ImperionThreadsMention` | `/me/mentions` | `threads_mentions` | `threads` |
| `Get-ImperionThreadsInsight` | `/{threads-user-id}/threads_insights` (profile) + `/{thread-id}/insights` (per post) | `threads_insights` (external_id `<entity_kind>:<entity_id>:<metric>:<period>:<end_time>`, entity_kind `profile`/`post`) | `threads` |

Writers: `Set-ImperionThreadsPostToBronze`, `Set-ImperionThreadsReplyToBronze`,
`Set-ImperionThreadsMentionToBronze`, `Set-ImperionThreadsInsightToBronze` — all thin
adapters over `Invoke-ImperionBronzePost` with the **exact 0208 column sets**
(change-detected upsert on `(tenant_id, source, external_id)`). A collector field absent from
the table is projected out and survives losslessly in `raw_payload`, so it can never break
the insert.

## Silver merge (local ownership, ADR-0026)

`Invoke-ImperionThreadsMerge` — idempotent set-based steps (NOT EXISTS /
ON CONFLICT DO NOTHING; INSERT-only, never UPDATE/DELETE on silver). Mirrors the documented
mapping (front-end #1347; OKF `interaction.md` + `social_metric.md` already carry the
`threads` rows):

1. `threads_posts` → `interaction` (source `threads`, kind `social_post`, direction
   **outbound** — our own content).
2. `threads_replies` → `interaction` (source `threads`, kind `social_comment`, direction
   **by author**: a reply authored by the root post's owner = outbound, else inbound — joined
   on `threads_posts.threads_user_id`).
3. `threads_mentions` → `interaction` (source `threads`, kind `mention`, direction
   **inbound**). v1 mentions are *of us* → they ride the contact-centric timeline (ADR-0124
   inbound-split D2); they are **NOT** lead captures, so there is **no `lead_hook`/
   `lead_capture` grant** for threads (the FB-DM-only distinction, 0208).
4. `threads_insights` → `social_metric` (platform `threads`; guarded numeric/timestamptz
   casts; ON CONFLICT DO NOTHING on the social_metric unique key → BI hub, ADR-0124 D9).

The merge keys interaction idempotency on `(source, external_ref)`; a re-run converges.

## Cadence & tasks

| Task | Entities | Cadence |
| --- | --- | --- |
| `Imperion-Threads` (`Invoke-ImperionThreadsSync`) | posts, replies, mentions, insights + merge | Daily @ 04:12 |

`Invoke-ImperionThreadsSync` collects all four feeds over one shared DB connection then runs
`Invoke-ImperionThreadsMerge` itself (merge co-locates with ingestion). Incremental window
from `IMPERION_THREADS_SINCE_DAYS` (default 7; 0 = full backfill); profile insights use
`IMPERION_THREADS_USER_ID` when set (per-post insights run regardless).

### Manual run path

```powershell
Import-Module ImperionPipeline
Initialize-ImperionContext
$env:IMPERION_THREADS_USER_ID = '<threads-user-id>'   # optional: profile insights
Invoke-ImperionThreadsSync
```

## Dormancy gate (fail-closed)

The whole source is **DORMANT** until three things land — and every entry point fails closed
until then, so the daily task is safe to register now:

1. **`conn-company-threads` seeded** — no active company `threads` connection row →
   `Resolve-ImperionThreadsToken` returns `$null` → `Invoke-ImperionThreadsSync` logs
   *"No active company Threads connection"* and exits cleanly (no collectors run).
2. **App Review cleared** — until the six scopes are approved, the Threads OAuth token can't
   be minted, so #1 holds.
3. **Migration 0208 applied in prod** — the bronze tables / enum values exist. An unapplied
   0208 makes the first DB write fail loud; the orchestrator's catch logs
   *"0208 applied?"* and exits. This repo **never creates tables** (schema is front-end-owned,
   §6).

Host task registration (`Register-ImperionTask` → `Imperion-Threads`) is itself **Mark-gated**
(unattended run-as identity; markd is non-admin). The next run after seeding converges
(idempotent upsert + NOT-EXISTS merge).

## Field assumptions — VERIFY LIVE

The flat-column field maps follow the published Threads API v1.0 reference, but versions and
permission tiers prune fields silently. Unreadable fields land NULL in the flat columns and
survive in `raw_payload` — **verify the flat columns against the first live run before
trusting them** (the `Get-ImperionMetaPagePost` precedent). Insight metrics are requested ONE
AT A TIME so a deprecated/unauthorized metric logs a warning and the run continues (the
`Get-ImperionMetaInsight` #100 precedent) — trim retired names from `-ProfileMetric` /
`-PostMetric` as they retire.

## Provenance & PII

`tenant_id` = Imperion's own (partner) tenant — first-party assets, not client data. Post,
reply, and mention **text is PII-adjacent — never log row contents**; bronze custody only.
Having a mention is **not** consent to contact (the system-wide lawful-basis guardrail).
