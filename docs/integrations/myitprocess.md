# Integration — myITprocess: vCIO strategic roadmap / QBR recommendations

myITprocess is the **vCIO advisory layer** (issue #195, ADR-0018): strategic roadmap / QBR /
assessment recommendations (initiatives, alignment scores, recommendations) scoped to an
**account** (not a device). These feed account health and the QBR narrative. A **read-only**,
pull-only scheduled bulk pull lands into Postgres bronze (`myitprocess_recommendations`).
**Read-only throughout — the app never writes myITprocess.**

> **Schema is front-end-owned (system CLAUDE.md §1).** `myitprocess_recommendations` is defined by
> front-end migration **0119** (front-end #674), **SHIPPED + prod-applied** — schema gate CLEAR.
> This collector NEVER creates the table; it **fails loudly** if absent (ADR-0005). The remaining
> gate is the API key (below).

## Source & auth
| Source | API | Auth |
| --- | --- | --- |
| myITprocess | myITprocess REST API (`https://api.myitprocess.com/api/v1`) | **`api_token` header** (URLs are NOT secret-bearing). SecretStore `myitprocess-api-key`, else Key Vault `myITprocess-API-Key` (cert SP) |

- **MSP-wide vendor credential** (ADR-0018 §2) — Imperion's own vCIO account, not per-client.
- **Read-only / pull-only** (no webhooks reach a home server — ADR-0001).
- **Paging:** `?page=N` from 1; the connect helper (`Invoke-ImperionMyItProcessRequest`) stops on a
  short page, hard-capped by `-MaxPages`. Throttling handled by the retry core.

## Entity & Postgres target (bronze)
| Entity | Source | Bronze table |
| --- | --- | --- |
| Recommendation | `myitprocess` | `myitprocess_recommendations` |

`myitprocess_recommendations` columns (front-end migration 0119, verified against prod):
`account_ref, assessment_name, recommendation_title, category, priority, status, target_date` + the
standard envelope (`tenant_id, source, external_id, collected_at, raw_payload, content_hash`).
`external_id` = the recommendation **id** (stable) → idempotent upsert.

## Flatten — straight to Postgres (IT Glue skipped)
**Borderline case (ADR-0018 §1, ADR-0006 §2 — the CRM/advisory exception).** myITprocess is
**strategic / account-scoped** data, not operational infrastructure, so it flattens **straight to
Postgres bronze and SKIPS the IT Glue hub** (same call as the KQM / DocuSign / EasyDMARC sources).
The account → client-tenant mapping is downstream silver (front-end); this bronze stamps the partner
tenant and preserves the raw account ref in `account_ref`.

## Downstream consumer (NOT done here)
Account-advisory rollups (alignment scores, open-recommendation counts) feed account health / QBR
narrative; "unprotected / stale-backup" counts from Datto BCDR roll up here too (ADR-0018 future
considerations). A dedicated silver `myitprocess` advisory concept is **a front-end call** (system
CLAUDE.md §11) — NOT implemented in this collector.

## Cadence
Daily (`scheduled-tasks/myitprocess/recommendations.task.ps1`). Roadmap / QBR / assessment
recommendations change slowly; stagger from the Datto tasks.

## Gates (Mark — block LIVE not BUILD)
1. **myITprocess API key** — provision `myitprocess-api-key` (SecretStore) or `myITprocess-API-Key`
   (Key Vault). Until then the resolver throws and the task logs + exits cleanly.
2. ~~Front-end `myitprocess_recommendations` bronze migration~~ — **SHIPPED + prod-applied**
   (migration 0119, #674).

## Still assumptions (no live access yet) — CONFIRM BEFORE LIVE
Modeled from the documented myITprocess API; **unverified** until the key lands (fallback chain +
lossless `raw_payload`):
- The base host, the auth header name (`api_token` vs `Authorization`), the resource path
  (`/recommendations`), the `data` collection wrapper, and the pagination scheme.
- Field names/casing (`id`, `clientId`, `assessmentName`, `title`, `category`, `priority`,
  `status`, `targetDate`).

## Cross-references
- This repo: **ADR-0018**, ADR-0001, ADR-0005, ADR-0006 (CRM/advisory exception — IT Glue skipped),
  ADR-0009.
- front-end **migration 0119 / #674** (the bronze tables).
- Issues: **#194** (epic), **#195** (this collector phase), **#196** (sibling — out of scope here).
- Siblings: [`datto-rmm.md`](datto-rmm.md), [`datto-bcdr.md`](datto-bcdr.md).
