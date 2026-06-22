# Integration — Pax8: distributor subscriptions, licenses, orders + companies

Pax8 is the cloud-marketplace **distributor** through which the MSP buys and provisions customer
licenses (issue #279, epic #1042). It holds the **actual licensed seat counts** the agreement
cost-reconciliation (#1041) trues up against contracted counts, and the **order** surface the
procure→provision→bill loop drives. A **read-only**, pull-only scheduled bulk pull lands four
object classes into Postgres bronze. **Read-only throughout — the app never writes Pax8.**

> **Schema is front-end-owned (system CLAUDE.md §1).** `pax8_companies` / `pax8_subscriptions` /
> `pax8_licenses` / `pax8_orders` are defined by front-end migration **0161** (front-end #1052).
> These collectors NEVER create the tables; they **fail loudly** if absent (ADR-0005). The
> remaining gates are (a) the migration being prod-applied and (b) the credential (below) — both
> Mark-gated; until then each task logs the gap and exits cleanly (dormant-safe).

## Source & auth
| Source | API | Auth |
| --- | --- | --- |
| Pax8 | Pax8 API v1 (`https://api.pax8.com`) | **OAuth2 client-credentials → short-lived BEARER**: a `client_id` + `client_secret` are POSTed to the token endpoint (`https://login.pax8.com/oauth/token`, audience `api://p8p.client`) for a bearer carried on every read |

- **MSP-wide COMPANY credential** — Imperion's own single distributor account (like Autotask /
  IT Glue / Datto), NOT per-client. One Pax8 account spans **many** customer companies.
- **Two-part credential.** Both halves resolve SecretStore-first / Key Vault-fallback via
  `Resolve-ImperionPax8Credential`: SecretStore `pax8-client-id` / `pax8-client-secret`, else Key
  Vault `Pax8-Client-Id` / `Pax8-Client-Secret` (cert SP). Names live in `config/secret-names.psd1`.
- **Token exchange owned by the connect helper** (`Invoke-ImperionPax8Request`): it exchanges the
  pair for a bearer and **never logs the secret or token**; the retry core redacts the
  token-exchange body + bearer headers. The secret never rides a querystring.
- **Read-only / pull-only** (no webhooks reach a home server — ADR-0001).
- **Paging:** Pax8 v1 returns Spring-style pages `{ content: [ ... ], page: { totalPages, number,
  ... } }`; the connect helper walks `page=0,1,…` with a fixed `size` until the last page
  (hard-capped by `-MaxPages`), tolerating a bare-array body pending live-shape verification.

## Entities & Postgres targets (bronze)
| Entity | Collector → writer | Bronze table | Role |
| --- | --- | --- | --- |
| Customer company | `Get-ImperionPax8Company` → `Set-ImperionPax8CompanyToBronze` | `pax8_companies` | join spine |
| Subscription | `Get-ImperionPax8Subscription` → `Set-ImperionPax8SubscriptionToBronze` | `pax8_subscriptions` | billing spine (#1041) |
| License assignment | `Get-ImperionPax8License` → `Set-ImperionPax8LicenseToBronze` | `pax8_licenses` | provision link → agreement/device (#280) |
| Order | `Get-ImperionPax8Order` → `Set-ImperionPax8OrderToBronze` | `pax8_orders` | procure side of procure→bill |

`external_id` = the Pax8 object `id` (stable) → idempotent upsert. **`tenant_id` carries the Pax8
partner/account id** (one distributor account spans many customers); the **per-customer key is
`company_id`** on each row (resolved to a silver `account` by the merge, #280). The full record is
preserved losslessly in `raw_payload`; the flat columns mirror migration 0161 exactly.

Column sets (migration 0161) + the standard envelope (`tenant_id, source, external_id,
collected_at, raw_payload, content_hash`):
- `pax8_companies`: `pax8_company_id, name, status`
- `pax8_subscriptions`: `pax8_subscription_id, company_id, product_id, product_name, quantity, status, billing_term, start_date`
- `pax8_licenses`: `pax8_license_id, subscription_id, company_id, product_id, assigned_to, quantity, status`
- `pax8_orders`: `pax8_order_id, company_id, status, ordered_at, total`

## Flatten path
Pure procurement / billing data: flattens **straight to Postgres** and **skips the IT Glue hub**
(ADR-0006), the same as Apollo / KQM / QBO. No IT Glue write surface is opened.

## Cadence & tasks
Daily, after the other company-credential collectors. Registered in `Register-ImperionTask`:
`Imperion-Pax8Companies` (02:06) → `Imperion-Pax8Subscriptions` (02:07) → `Imperion-Pax8Licenses`
(02:08) → `Imperion-Pax8Orders` (02:09). Companies run first because the other three carry
`company_id` against them and the merge (#280) laterals on it. One scheduled task per (source,
entity) — the CLAUDE.md §1 "many small jobs" standard.

## Merge (sibling issue #280)
Bronze→silver merge **co-locates with ingestion** (LP ADR-0026): LP ingests Pax8, so LP owns the
merge — `Invoke-ImperionPax8Merge` (idempotent replace-from-source) resolving each Pax8 company to
a silver `account` and linking licenses to agreement lines / devices, producing the actual-count
side of the #1041 true-up. Built as the follow-up issue, not here.

## CONFIRM BEFORE LIVE USE
The token endpoint host/path, the `audience` value, the API origin, the page-wrapper property
names, and the per-object field names are **modeled from the published Pax8 API docs but
UNVERIFIED** against the real account until the credential lands (the Datto/KQM precedent). Each
flat column leads with the most likely source name and keeps a short fallback chain; an unmatched
column lands NULL and nothing is lost (full payload in `raw_payload`). The `pax8_licenses`
`-Path` (`/v1/licenses`) is the most likely to need correcting — Pax8 may surface seat assignments
under a usage-summary endpoint; it is a single constant to fix on the first live pull.

## Security
- **No secrets in repo** (CLAUDE.md §8). Only secret *names* live in `config/secret-names.psd1`.
- Bronze is **PII-adjacent** (company names, assignee identifiers) and access-controlled (ADR-0039);
  structured logs record **counts only**, never names or amounts.
- New write capability would be an explicit, approved grant — this integration adds none (read-only).
