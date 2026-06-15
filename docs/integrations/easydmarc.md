# Integration — EasyDMARC: domain / DMARC posture ingestion

**Purpose.** EasyDMARC is Imperion's 3rd-party DNS/DMARC provider. This source ingests
per-domain **email-authentication posture** (DMARC / SPF / DKIM / BIMI status + setup
status) into **security-posture bronze** — this repo's posture ownership (system CLAUDE.md
§1). It is **security-posture evidence** about a client `account` and its domains, so it
flattens **straight to Postgres** and **skips the IT Glue hub** (same call as KQM/DocuSign).

> **Status: collector CODE shipped, live ingestion GATED (issue #122).** The collector is
> dormant until **both** (a) the EasyDMARC API key is provisioned (Mark-gated — the plan
> must include API access) and (b) the front-end bronze migration for `easydmarc_domains`
> is applied. The bronze table is a **schema change owned by the front-end repo**
> (system CLAUDE.md §1) and is proposed in **ImperionCRM issue #581**; no migration
> is added in this repo. The daily task logs the gap and exits cleanly until both land.

## Source & auth
| Source | API | Auth |
| --- | --- | --- |
| EasyDMARC | read-only REST `https://api.easydmarc.com` | API key (generated in Profile → APIs) sent as **`Authorization: Bearer <apiKey>`** — SecretStore `easydmarc-api-key` (mirror), else Key Vault `EasyDMARC-API-Key` (original, kv-imperioncrm-prd) via the cert SP |

- **Company credential, not per-client.** The key is Imperion's MSP account; EasyDMARC's
  **Organizations** endpoint group provides the org→client mapping for per-tenant
  isolation (a follow-up once verified against a live key — see "Unknowns" below).
- **Header auth → URLs are NOT secret-bearing** (unlike KQM's `?apikey=`). No special URL
  redaction needed.
- **Read-only / pull-only** — no webhooks surfaced in the public docs, so the scheduled
  bulk poll belongs **here** per the cloud/local boundary (CLAUDE.md §1).
- **Rate limits:** "rate limited per API key" (no figures published) — verify on first
  live pull; the docs recommend batch DNS lookups to optimize. One daily page-walk of the
  domain list is well inside any plausible budget.
- **Paging:** assumed `?page=N` from 1 with a `data` array + a `meta` block; the connect
  layer stops on a short page or a reported `meta.last_page`. **Confirm on first live pull.**

## Entities & Postgres targets (bronze)
| Entity | Source | Bronze table (proposed) | external_id |
| --- | --- | --- | --- |
| Domain / DMARC posture | `easydmarc` | `easydmarc_domains` (front-end issue #581) | domain name |

`easydmarc_domains` proposed columns (ADR-0039 per-source envelope): `domain,
organization_ref, setup_status, dmarc_policy, dmarc_status, spf_status, dkim_status,
bimi_status` + the standard envelope (`tenant_id, source, external_id, collected_at,
raw_payload, content_hash`). PK `(tenant_id, source, external_id)`.

**Deferred (separate micro-PR, gated on a live key):** `easydmarc_aggregate_reports`
(DMARC RUA aggregate analytics — domain, window, total_volume, compliant_count, pass_rate,
spf/dkim aligned counts). Its field names are unverified without a live key; it follows
once #122 flips to ready-for-agent.

## Flatten
Standard pattern: flatten each domain to `[PSCustomObject]` with the posture attributes we
care about + the envelope. `Get-ImperionEasyDmarcDomain` leads each flat column with the
most likely source name and keeps a short fallback chain (casing/snake-case drift
tolerated); misses land NULL, `raw_payload` keeps everything.

## Cadence
Daily. See [`../../scheduled-tasks/`](../../scheduled-tasks) — `easydmarc/domains`.

## Provenance
Posture rows are stamped `source` / `collected_at` per the system provenance guardrail
(CLAUDE.md §8). Domain health is operational truth, not personal data; no PII is collected.

## Unknowns needing a live key (verify-first, like KQM #98 / #427)
- Exact rate-limit numbers and the pagination scheme (page vs cursor).
- The exact domain object field names (the flatten map's leading names are best-effort).
- The Organizations endpoint shape for the org→client tenant mapping (today every row is
  stamped the partner tenant; per-client mapping is the follow-up).
- The aggregate-report (RUA) field names (the deferred second table).
- Whether Imperion's current EasyDMARC plan includes API access.
