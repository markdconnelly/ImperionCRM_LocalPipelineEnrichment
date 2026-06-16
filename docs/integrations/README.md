# Integrations

_ImperionCRM_LocalPipelineEnrichment — `docs/integrations`_

One doc per source: auth, exact onboarding-app Graph permission grants, rate limits, cadence, fields, provenance, change-detection, retry.

**RMM / managed estate** (issue #195, ADR-0018 — MSP-wide vendor keys, gated on provisioning):
- [`datto-rmm.md`](datto-rmm.md) — Datto RMM device inventory + patch/AV state →
  `datto_rmm_devices`. Auth: API-key→short-lived bearer exchange.
- [`datto-bcdr.md`](datto-bcdr.md) — Datto BCDR per-device backup posture →
  `datto_bcdr_backups` (joins on `device_uid`). Auth: `Authorization: Bearer` header.
- [`myitprocess.md`](myitprocess.md) — myITprocess vCIO roadmap/QBR recommendations →
  `myitprocess_recommendations` (account-scoped; straight to Postgres, skips IT Glue).
  Auth: `api_token` header.

**Spikes / assessments** (not yet wired collectors):
- [`graph-usage-reports-spike.md`](graph-usage-reports-spike.md) — Microsoft Graph usage
  reports (`Reports.Read.All`) for client analytics (#144). Verdict: **defer** — build a
  narrow aggregate-only collector when prioritized; per-user detail rejected on PII grounds.

> Part of the system-wide `/docs` standard (front-end `CLAUDE.md` §8). See [../../CLAUDE.md](../../CLAUDE.md).

