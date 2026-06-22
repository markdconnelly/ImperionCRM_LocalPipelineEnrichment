# STATE — ImperionCRM_LocalPipelineEnrichment

Volatile / operational status for this repo. **This file goes stale by design** —
the durable contract lives in `CLAUDE.md`; anything dated, in-flight, or run-specific
lives here. When a fact here hardens into a rule, move it to `CLAUDE.md`; when it is
done or superseded, prune it.

Last reviewed: **2026-06-20.**

---

## Heads-up — stale-wording guards

- **GDAP is scrapped (2026-06-12).** Client M365 access is the per-client onboarding
  app (pipeline ADR-0018, `CLAUDE.md §3`). If you find lingering "GDAP-primary" wording
  or a `$activeGdapRelationships`-style code path, it is **stale** — the onboarding-app
  model is authoritative. Residual GDAP machinery (fail-closed sweep / health checks) is
  **dormant code**: it skips cleanly because no partner app is configured and reports zero
  usable tenants. Do not build against it; do not treat it as a live fallback. Its
  retirement is a separate follow-up.
- **M365 / Azure estate is discovered, not static (2026-06-19, #234).** Collectors fan
  out per consented tenant from the silver `account_tenant` table, resolving each tenant's
  enterprise-app credential as **cert-or-secret**. The per-client app credential model is
  still settling (backend #217 / LP #250 open).
- **Merge co-locates with ingestion (ADR-0026).** LP owns the bronze→silver merge for the
  sources it bulk-ingests. If you read "silver merge is cloud-only" anywhere, it is stale —
  `CLAUDE.md §6` + ADR-0026 win.

---

## Merge migration (ADR-0026) — in flight

Whichever plane *ingests* a source's bronze owns its merge (`CLAUDE.md §6`). The cutover
from the cloud Pipeline to LP is gap-free because both copies are replace-from-source on the
same source label — **ship the LP merge first (additive), cede the cloud copy second**, and
never cede before the LP copy is verified writing in prod.

- **`cloud_asset` — CEDED + MERGED** (Pipeline #135 / PR #138, 2026-06-19). PL #133 was
  deployed, so this ended a live double-merge, not a no-op. `Invoke-ImperionCloudAssetMerge`
  (#241). `cloud_asset` = 23 rows live on-prem via the LP merge.
- **M365 directory groups → LP — HOLD.** `Invoke-ImperionM365DirectoryMerge` (#239) cedes
  the cloud `mergeDirectoryGroups` via Pipeline #134, which is **STILL ON HOLD** —
  `m365_groups` / `m365_members` bronze is empty because the entra collectors have not been
  run.

The cloud Pipeline retains only the live/webhook-driven merge (the `website_*`-fed
contact/account/device/contract/ticket/opportunity/expense sweep + DocuSign).

`Invoke-ImperionPostureMerge` / Meta / DNS are the established LP-merge precedent now
generalized.

---

## Credential registry (ADR-0103) — in flight

`connection` extended into a KV credential registry (scope personal/company/client +
`account_id` + cert-or-secret). Multi-tenant resolver epic #255
(`Resolve-ImperionTenantCredential` #257) wired into the m365 (#250) and ARM (#258)
collectors.

- **UniFi COMPLETE (collector + bronze):** BE #233/PR234 provider_config + **LP #259/PR269
  multi-console sweep** + FE #964/PR965 register form + **FE migration `0162` `unifi_devices`
  bronze (#1053/#73) — prod-applied (table live, EMPTY pending a registered console)**. The
  on-prem writer/collector docs are reconciled to the landed table (#281).
- **Mark-gated / still pending:** prod-apply migrations 0150 + 0151; register a client UniFi
  console (the registry is **EMPTY in prod**, so the sweep self-gates + no-ops). Follow-up:
  on-prem `Invoke-ImperionUniFiMerge` bronze→silver `device` (ADR-0026, #73 acceptance).

---

## OKF semantic-layer sync

The enrichment agent that will auto-sync the OKF bundle (`docs/database/semantic-layer/`
in the front-end) is this repo's **#175**; vectorizing the bundle into gold is **#176**
(blocked on front-end expansion #536). Until those land, OKF concept-file + coverage-matrix
updates for any silver-shape change are the author's manual responsibility (front-end
docs-gate, issue #535).

CI: the `okf-sync` job gates PRs that change per-source bronze ingestion — link an
ImperionCRM OKF issue/PR in the body, or label `okf-sync`; if silver meaning is unaffected,
label `okf-not-affected` with a justification.

---

## Open / tracked follow-ups

- **#175** — enrichment agent to auto-sync the OKF bundle.
- **#176** — vectorize the OKF bundle into gold (blocked on front-end #536).
- **#250 / backend #217** — per-client app credential model still settling.
- **#239 / Pipeline #134** — M365 directory merge cede (HOLD: entra collectors not run).
- **#73** — LP `unifi_devices` bronze (Mark-gated).
- **Schema reconciliation** — several §5 sources are **new** to the schema
  (`kqm_proposal`, `docusign_contract`, `autotask_contract`, `autotask_ticket`, the
  `*_devices` set) and need front-end migrations first. Bronze table-naming convention
  (`{source}_companies` vs `_bronze` suffix) must be reconciled with the front-end repo,
  which defines the real tables. Track as an ADR + cross-repo checklist.
- **Unattended bring-up** — Option B (DPAPI SecretStore, no CMS — the cert cannot do
  Document Encryption) chosen 2026-06-17; `svc-imperion` + vault configured; code + ADR-0002
  edits owed as a PR.

---

## Architecture-deepening backlog (2026-06-18 review)

Cross-4-repo `/improve-codebase-architecture` filed LP issues **#228 (shipped) / #229**;
recurring shape = N shallow adapters → one deep module + a config table. Tackle order
across repos started at #228.
