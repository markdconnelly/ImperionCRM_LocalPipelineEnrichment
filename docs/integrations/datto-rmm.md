# Integration — Datto RMM: managed-device inventory + patch/AV state

Datto RMM is the **live device inventory** of the managed estate (issue #195, ADR-0018): every
managed endpoint, its patch state, AV status, and asset/software inventory. A **read-only**,
pull-only scheduled bulk pull lands into Postgres bronze (`datto_rmm_devices`). **Read-only
throughout — the app never writes Datto RMM.**

> **Schema is front-end-owned (system CLAUDE.md §1).** `datto_rmm_devices` is defined by front-end
> migration **0119** (front-end #674), which is **SHIPPED + prod-applied** — so the schema gate is
> CLEAR. This collector NEVER creates the table; it **fails loudly** if absent (ADR-0005). The
> remaining gate is the API key (below).

## Source & auth
| Source | API | Auth |
| --- | --- | --- |
| Datto RMM | Datto RMM REST API (per-platform host, e.g. `https://<zone>-api.centrastage.net`) | **API-key → short-lived BEARER exchange** at `/auth/oauth/token`; the bearer is carried on every read. SecretStore `datto-rmm-api-key`, else Key Vault `Datto-RMM-API-Key` (cert SP) |

- **MSP-wide vendor credential** (like Autotask / IT Glue / KQM) — NOT per-employee OAuth, NOT a
  per-client onboarding token (ADR-0018 §2).
- **Token exchange owned by the connect helper** (`Invoke-ImperionDattoRmmRequest`): it exchanges
  the API key for a bearer and **never logs the token**; the retry core redacts bearer headers +
  token-exchange bodies. The API key never rides a querystring.
- **Read-only / pull-only** (no webhooks reach a home server — ADR-0001).
- **Paging:** Datto RMM wraps lists as `{ pageDetails: { nextPageUrl, ... }, devices: [ ... ] }`;
  the connect helper follows `pageDetails.nextPageUrl` until null (hard-capped by `-MaxPages`).

## Entity & Postgres target (bronze)
| Entity | Source | Bronze table |
| --- | --- | --- |
| Managed device | `datto_rmm` | `datto_rmm_devices` |

`datto_rmm_devices` columns (front-end migration 0119, verified against prod): `device_uid,
hostname, site_name, operating_system, last_seen, patch_status, antivirus_status, agent_version,
device_type, soft_delete` + the standard envelope (`tenant_id, source, external_id, collected_at,
raw_payload, content_hash`). `external_id` = the Datto RMM device **UID** (stable) → idempotent
upsert. The **full asset/software inventory** is preserved losslessly in `raw_payload`; the flat
columns are the device-existence + live-state facts the silver merge keys on.

## Flatten & IT Glue path
Standard pattern (CLAUDE.md §6): flatten device → `[PSCustomObject]` with the columns above + the
envelope. As **operational/infrastructure data** Datto RMM belongs on the flatten → IT Glue →
Postgres path (ADR-0006) — the downstream silver/relationship layer relates device → IT Glue
Organization / Configuration / Contact. **This bronze collector writes Postgres only; the IT Glue
documentation write is a separate, scoped/gated step (CLAUDE.md §6) and is NOT performed here.**

## Downstream consumer — device-merge precedence (NOT done here)
Datto RMM is a **strong machine device authority**. The silver `device` merge precedence is
`website > datto_rmm > m365 > itglue` (ADR-0018 §2): below the `website` resurrection guard
(front-end ADR-0039, untouched), above `m365`/`itglue` for device-existence + live-state. **That
silver merge is owned by the front-end / cloud Pipeline — this on-prem collector only writes bronze
faithfully.** The precedence change + the BCDR backup-posture field merge are proposed back to the
front-end OKF `device` concept + `coverage-matrix.md` (system CLAUDE.md §11) at merge.

## Cadence
Daily (`scheduled-tasks/dattormm/devices.task.ps1`). Device inventory + patch/AV state is
slow-changing relative to a daily page-walk. Stagger from other managed-estate tasks.

## Gates (Mark — block LIVE not BUILD)
1. **Datto RMM API key** — provision `datto-rmm-api-key` in the SecretStore (or `Datto-RMM-API-Key`
   in Key Vault). Until then the resolver throws and the task logs + exits cleanly (idempotent
   re-run converges). The 180-day retention sweep is the **sibling #196** concern, not here.
2. ~~Front-end `datto_rmm_devices` bronze migration~~ — **SHIPPED + prod-applied** (migration 0119,
   #674). No longer a gate.

## Still assumptions (no live access yet) — CONFIRM BEFORE LIVE
Modeled from the documented Datto RMM API; **unverified against the real account** until the key
lands (the flatten keeps a fallback chain, `raw_payload` is lossless — the KQM/EasyDMARC precedent):
- The per-platform base host and the `/auth/oauth/token` exchange grant/params.
- The device list path (`/v2/account/devices`), the `pageDetails.nextPageUrl` wrapper, and the
  `devices` entity property.
- Device field names/casing (`uid`, `hostname`, `siteName`, `operatingSystem`, `lastSeen`,
  `patchManagement.patchStatus`, `antivirus.antivirusStatus`, `agentVersion`,
  `deviceType.category`, `softDelete`).
- The Datto RMM site → client-tenant mapping (a follow-up; bronze stamps the partner tenant today).

## Cross-references
- This repo: **ADR-0018** (RMM / managed-estate sources + device-precedence revisit), ADR-0001
  (cloud keeps webhooks), ADR-0005 (source catalog, fail-loud-on-missing-table), ADR-0006 (IT Glue
  hub), ADR-0009 (key-resolution pattern).
- front-end **ADR-0039** (per-source bronze + `website` resurrection guard — the precedence anchor),
  **migration 0119 / #674** (the bronze tables).
- Issues: **#194** (epic — source-catalog expansion), **#195** (this collector phase), **#196**
  (sibling — security incidents + 180d retention, out of scope here).
- Siblings: [`datto-bcdr.md`](datto-bcdr.md), [`myitprocess.md`](myitprocess.md).
