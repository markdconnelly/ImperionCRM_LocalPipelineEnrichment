# STATE — ImperionCRM_LocalPipelineEnrichment

Volatile / operational status for this repo. **This file goes stale by design** —
the durable contract lives in `CLAUDE.md`; anything dated, in-flight, or run-specific
lives here. When a fact here hardens into a rule, move it to `CLAUDE.md`; when it is
done or superseded, prune it.

Last reviewed: **2026-06-25.**

---

## M365 hydration — registry-driven fan-out (2026-06-25, #358)

The M365 estate collectors now fan out over the **consented-tenant registry** by default
(`Get-ImperionConsentedTenant`: `account_tenant ⨝` an active `m365` `connection`), not the
`IMPERION_M365_TENANT_IDS` env var (#358, ADR-0030 Decision #4 — the "registry-as-enable" half).
A GUI-mapped, credentialed tenant hydrates on the next run with **no host env edit**.

- **HOST ACTION (Mark):** **unset `IMPERION_M365_TENANT_IDS`** on the home server so the registry
  drives discovery (if it is still set, it pins the sweep to that subset — back-compat). Then run
  the M365 tasks (or wait for the nightly).
- **Grounded 2026-06-25 (pg-MCP):** 4 tenants are mapped + credentialed (Imperion `49307c12`,
  M365KJLA `bb2a08c8`, M365IPG `d3f6481e`, M365RGC `b5a76f96`) — all have `account_tenant` + live
  `entity_xref` + an active `m365` `connection`. Pre-#358 only Imperion's tenant was in bronze
  because the env var was Imperion-only. After the host action above, all four should sweep
  (each fail-isolated; an unconsented tenant logs Warn + skips).
- **Still per-tenant Mark-gated:** each client tenant's onboarding app must be **admin-consented**
  (`build/New-ImperionClientOnboardingApp.ps1` run as that tenant's Global Admin) or its Graph
  reads 403 — an active registry row is not proof of consent.
- **Slice 3b (#359) — tenant-outer driver `Invoke-ImperionTenantHydration` BUILT (additive):**
  enumerates consented tenants once, acquires each tenant's Graph token once (reused across routines
  via the `(tenant,resource)` cache), then runs the 14 estate collectors pinned to that tenant
  (tenant-outer). Per-tenant fail-closed skip + per-routine isolation + one Metric summary. **Landed
  additive — the per-collector M365 scheduled tasks are UNCHANGED (still the safety net); the driver
  is callable but not yet the scheduled entry.**
  - **VERIFIED ON HOST 2026-06-25:** `Invoke-ImperionTenantHydration` ran tenant-outer across all 4
    tenants (`Tenant hydration complete`); M365 users wrote 152/87/… for the non-first tenants — the
    exact writes the loop-var bug would have dropped. Token reused per tenant. The `Warn` lines are
    pre-existing per-source issues (group-members 23502 #366, per-tenant consent gaps, gated tables),
    all fail-isolated — not driver faults.
  - **CUTOVER LANDED (#359 pt2):** `Register-ImperionTask` now registers ONE `Imperion-TenantHydration`
    @ 03:02 and the 14 per-collector M365 entries are REMOVED (`SecurityIncidents` + `PurviewCompliance`
    stay — not sweep-based). **DORMANT until Mark re-runs `Register-ImperionTask` on the host** (admin)
    to apply the new task set. The per-collector cmdlets stay exported + callable (the driver invokes
    them), just not separately scheduled.
  - Bug caught pre-merge: the inner loop var `$routine` collided (case-insensitively) with the
    `$Routine` param → every tenant after the first ran only its last routine; fixed (`$routineName`).
  - OKF: this slice is **orchestration only** (a `-TenantId` passthrough + the driver) — it changes
    no bronze shape, source-of-record, or silver meaning, so it carries `okf-not-affected` (ADR-0104).

---

## Live-caught regressions

- **Group-membership 23502 null `member_external_id` (2026-06-25, #366 — FIXED).** The first
  tenant-outer hydration run failed `Invoke-ImperionEntraGroupMemberSync` for **every** tenant
  (`m365_group_members` empty everywhere) — Graph returned at least one id-less member, whose null
  `member_external_id` hit the NOT NULL column (migration 0079). `Get-ImperionM365GroupMember` now
  **skips id-less members** (no usable join key → no valid edge) and counts them (`skipped_members`),
  so one bad member never aborts the tenant's membership upsert. Unblocks the directory merge
  (`contact_enrichment` `directory_groups`). `okf-not-affected` (a null key was never a valid row).
- **Intune detected-apps v1.0 vs beta (2026-06-25, #369 — FIXED).** `Get-ImperionIntuneManagedApp`
  called `/v1.0/deviceManagement/managedDevices/{id}/detectedApps` → 400 "segment 'detectedApps' not
  found" (that per-device navigation is beta-only). Now uses `/beta/...detectedApps` (device list
  stays v1.0). `intune_managed_apps` (mig 0148) is applied + app holds `DeviceManagementApps.Read.All`,
  so the feed lights up on the next host run. CONFIRM-BEFORE-LIVE on the `detectedApp` field shapes.
- **Intune detected-apps id-less abort (2026-06-26, #374 — FIXED).** Live host run: 3/4 tenants
  skipped with "The property 'id' cannot be found" — a direct `$app.id`/`$device.id` read throws
  under StrictMode when a `detectedApp`/device omits `id`, aborting the whole tenant (only RGC, 1
  device, populated → `intune_managed_apps`=91). Now reads via `Get-ImperionMember` and `continue`s
  past the id-less row. Re-verify per-tenant counts on the next host run.
- **Info-protection collector drift (2026-06-26, #372 — FIXED).** Earlier framing was wrong:
  the sensitivity-label + custom-sec-attr 42P01s were NOT a missing FE migration. FE #575
  prod-applied the bronze tables as `m365_sensitivity_labels` + `entra_custom_security_attributes`;
  the collectors wrote the non-existent `sensitivity_labels` / `custom_security_attribute_definitions`
  (the `imperion-lp-collector-schema-drift` pattern). #372 renames the target tables, reworks the
  flat maps to the applied columns (`label_id`/`name`/`priority`/`is_active` ·
  `attribute_set`/`name`/`data_type`/`status`; surplus stays in `raw_payload`), and moves the
  sensitivity GET to `/beta` (same class as #369). CONFIRM-BEFORE-LIVE: the beta sensitivity path +
  app permission on the first real pull.
- **DB credential resolver enum cast (2026-06-24, #330 — FIXED).** After the #320 deploy,
  both registry resolvers (`Resolve-ImperionCompanyCredential`, `Resolve-ImperionTenantCredential`)
  threw `42883: operator does not exist: connection_provider = text` on every run — `connection.provider`
  is an enum and `@provider` bound as text with no cast. It broke all registry-backed company
  vendors (itglue/pax8/myitprocess/televy/quotemanager) **and** the m365/azure client-credential
  path (`Get-ImperionRegisteredTenantToken`), so 365/Azure could not hydrate even with the dead
  cred row purged. Fix: `provider = @provider::connection_provider` (the `@t::uuid` precedent). The
  resolver Pester tests mock the DB, so the SQL is now pinned in the capture tests — but the only
  true proof is a live host re-run after deploy.
- **account_tenant/connection uuid-vs-text param casts (2026-06-24, #334 — FIXED).** After #330/#331
  deployed, the m365/azure path surfaced the NEXT type mismatch (`42883: operator does not exist:
  text = uuid`): `ImperionContext.ps1` cast `tenant_id = @t::uuid` but `account_tenant.tenant_id` is
  **text**, and `Resolve-ImperionTenantCredential` compared `account_id = @account` (text param) to
  the **uuid** `connection.account_id`. Fixes: `tenant_id = @t` (text=text) + `account_id = @account::uuid`.
  This was the last cast-class blocker for Imperion 365/Azure hydration. Verified vs `information_schema`;
  same live-only class as #330 (mocks can't catch it).

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
  (#241). `cloud_asset` = **101 rows** live on-prem via the LP merge (2026-06-25; was 23 — the
  ARM collector now fans out per consented tenant, ADR-0030).
- **M365 directory groups → LP.** `Invoke-ImperionM365DirectoryMerge` (#239) cedes the cloud
  `mergeDirectoryGroups` via Pipeline #134. The entra collectors now run — `m365_groups` = **99**,
  `entra_role_assignments` = **26** live in bronze (2026-06-25) — so the cede is unblocked;
  confirm the LP merge is writing `contact_enrichment.directory_groups` in prod before ceding
  the cloud copy.

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

### Credentialed-source hydration — vendor-connect blob handling (2026-06-22)

The company-scope vendor credentials are custodied as **JSON credential blobs** in Key Vault
under the standardized `conn-company-<provider>` name (FE/BE seed the blob; the registry GUI
writes it). The on-prem resolver path now matches that shape:

- **`ConvertFrom-ImperionCredentialBlob`** parses the `conn-company-*` JSON blob and extracts the
  needed field (e.g. `apiKey`); the per-vendor `Resolve-Imperion<Vendor>ApiKey` helpers and the
  shared `Resolve-ImperionVendorSecret` (#228) route through it (#291/#293 IT Glue/KQM/Telivy;
  #299/#301 the blob parse + myITprocess reroute). Earlier these resolvers read **raw-string**
  KV secrets / wrong KV names — that drift is fixed.
- **Now LIVE in bronze (prod):** **IT Glue = 716** (27 companies + 234 contacts + 455 devices),
  **KQM** and **myITprocess** pulling (small live row counts). myITprocess transport + field map
  also verified live (#297/#303) and the doc reflects it.
- **Still blocked: Telivy** — resolver standardized (#291) but the source stays **dormant** until
  its credential lands (no `conn-company-telivy` blob in prod yet); the collector logs + exits
  cleanly.
- Datto RMM/BCDR remain on legacy named secrets (not yet on the `conn-company` blob path) — see
  the [data-in light-up runbook](runbooks/data-in-light-up.md) Step 1.

### DB-authoritative company credential resolution (ADR-0029, epic #318) — keystone MERGED

> Full onboarding map: [`security/credential-resolution.md`](security/credential-resolution.md).

Company vendor creds follow the **same DB→Key Vault link the backend/cloud use**: LP reads the
`connection` registry row → `keyvault_secret_ref` → KV blob (mirror of the client-scope
`Resolve-ImperionTenantCredential`). End-state: the **only** SecretStore secret LP reads is the app
credential that mints the KV token.

- **Keystone MERGED (#319/#320, ADR-0029 Accepted):** `Resolve-ImperionCompanyCredential` +
  vendor-catalog cutover. Registry-backed (itglue/televy/quotemanager/myitprocess/pax8/darkwebid)
  resolve DB→KV; LP-only vendors with no registry row (cdw/easydmarc/datto rmm+bcdr/amazonbusiness;
  + meta, pending token-type reconciliation) read a named KV secret. SecretStore-mirror tier removed.
- **Two live cast-class regressions caught + FIXED post-deploy** (mocks can't catch them) — see
  *Live-caught regressions* above: enum cast `connection_provider` (#330) and `account_tenant`/
  `connection` uuid-vs-text casts (#334). These were the last blockers for registry-backed hydration.
- **Still on SecretStore (own follow-up PRs):** autotask, qbo (backend owns the OAuth refresh —
  backend #385), voyage, mileiq, docusign. The `secret-names` cleanup + the `CLAUDE.md §2/§7`
  rewrite land with the last one. Legacy-name retirement is **#292**.
- **Registry data (GUI/Mark):** `gdap` row = **purged in prod** (done); `docusign` + `apollo` rows
  remain `status=error` (stale `kv://` ref) → re-seed via the GUI before those providers resolve.

### Tenant-driven 365 + Azure hydration (ADR-0030, epic #324) — slices MERGED

The Graph **and** ARM data planes resolve **every** tenant (home included) from the registry via
`Resolve-ImperionTenantCredential` — no home special-case. The node cert SP is reduced to
infra/bootstrap tokens only (PG/KV/Storage) and holds **no Graph/ARM data reach**.

- **MERGED:** uniform per-tenant resolver + rename `Get-ImperionTenantAppToken` →
  `Get-ImperionRegisteredTenantToken`, ARM reuses the `m365` app (#327/#328, ADR-0025…). The
  account ambiguity is resolved — the dead config-SP cert `m365` row is purged; the two remaining
  `m365` rows are both `auth_method='secret'`, active (live registry, 2026-06-25).
- **One cloud grant assumed:** Global Reader on each onboarding app's tenant root management group
  (the ARM read). **#329** neutralizes the `PartnerTenantId` config key (home-agnostic naming).
- **Known 403 gaps (Mark/consent):** auth-methods report needs `AuditLog.Read.All` (#340); mail +
  Teams collectors need `IMPERION_M365_MAILBOXES` / `IMPERION_M365_USERS` host config (#341).

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
