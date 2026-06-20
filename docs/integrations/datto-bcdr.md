# Integration — Datto BCDR: per-device backup posture

Datto BCDR / backup answers **"is this machine actually recoverable?"** (issue #195, ADR-0018):
protected / unprotected, last-good-backup, last-screenshot-verification, per device. A **read-only**,
pull-only scheduled bulk pull lands into Postgres bronze (`datto_bcdr_backups`). **Read-only
throughout — the app never writes Datto BCDR.**

> **Schema is front-end-owned (system CLAUDE.md §1).** `datto_bcdr_backups` is defined by front-end
> migration **0119** (front-end #674), **SHIPPED + prod-applied** — schema gate CLEAR. This
> collector NEVER creates the table; it **fails loudly** if absent (ADR-0005). The remaining gate is
> the API key (below).

## Source & auth
| Source | API | Auth |
| --- | --- | --- |
| Datto BCDR | Datto BCDR / backup REST API (`https://api.datto.com/...`) | **`Authorization: Bearer <apiKey>`** header (URLs are NOT secret-bearing). SecretStore `datto-bcdr-api-key`, else Key Vault `Datto-BCDR-API-Key` (cert SP) |

- **MSP-wide vendor credential** (ADR-0018 §2) — not per-employee OAuth, not a per-client token.
- **Read-only / pull-only** (no webhooks reach a home server — ADR-0001).
- **Paging:** `?page=N` from 1; the connect helper (`Invoke-ImperionDattoBcdrRequest`) stops on a
  short page, hard-capped by `-MaxPages`. Throttling (429 + Retry-After) is handled by the retry core.

## Entity & Postgres target (bronze)
| Entity | Source | Bronze table |
| --- | --- | --- |
| Device backup posture | `datto_bcdr` | `datto_bcdr_backups` |

`datto_bcdr_backups` columns (front-end migration 0119, verified against prod): `device_uid,
protected_status, last_backup_at, last_good_backup_at, backup_type, agent_version` + the standard
envelope (`tenant_id, source, external_id, collected_at, raw_payload, content_hash`). `external_id`
= the Datto device **UID** (stable) → idempotent upsert. The **`device_uid` is the join** to the
Datto RMM device record (ADR-0018 §1).

## Flatten & IT Glue path
Standard pattern: flatten agent/backup posture → `[PSCustomObject]` with the columns above + the
envelope. As operational data, backup posture relates to the same device/Configuration in IT Glue
(ADR-0006) — that documentation write is a separate, scoped/gated step (CLAUDE.md §6) and is **NOT**
performed by this bronze collector.

## Downstream consumer — field-scoped device merge (NOT done here)
Datto BCDR contributes the **backup-posture fields** to the unified silver `device` (ADR-0018 §2:
field-scoped merge, joining on `device_uid`) — no other source carries them, so it does not compete
for device-identity precedence. **That `device` silver merge stays cloud-Pipeline owned** — it is
part of the webhook/`website_*`-fed contact/account/**device** sweep that remains in the cloud under
ADR-0026 ("merge co-locates with ingestion") — **this collector only writes bronze.** (Merges this
repo *does* own — posture, Meta, DNS, M365 directory, `cloud_asset` — are in
[`../collector-inventory.md`](../collector-inventory.md) (§ "Bronze→silver merge").)

## Cadence
Daily (`scheduled-tasks/dattobcdr/backups.task.ps1`). Per-device backup posture is checked daily;
stagger from the Datto RMM device task.

## Gates (Mark — block LIVE not BUILD)
1. **Datto BCDR API key** — provision `datto-bcdr-api-key` (SecretStore) or `Datto-BCDR-API-Key`
   (Key Vault). Until then the resolver throws and the task logs + exits cleanly.
2. ~~Front-end `datto_bcdr_backups` bronze migration~~ — **SHIPPED + prod-applied** (migration 0119,
   #674).

## Still assumptions (no live access yet) — CONFIRM BEFORE LIVE
Modeled from the documented Datto API; **unverified** until the key lands (fallback chain +
lossless `raw_payload`):
- The base host, the resource path (`/v1/bcdr/agents`), the `items` collection wrapper, and the
  pagination scheme.
- Field names/casing (`deviceUid`, `protectedStatus`, `lastBackup`, `lastGoodBackup`, `backupType`,
  `agentVersion`).

## Cross-references
- This repo: **ADR-0018**, ADR-0001, ADR-0005, ADR-0006, ADR-0009.
- front-end **migration 0119 / #674** (the bronze tables), **ADR-0039** (device-merge anchor).
- Issues: **#194** (epic), **#195** (this collector phase), **#196** (sibling — 180d retention,
  out of scope here).
- Siblings: [`datto-rmm.md`](datto-rmm.md), [`myitprocess.md`](myitprocess.md).
