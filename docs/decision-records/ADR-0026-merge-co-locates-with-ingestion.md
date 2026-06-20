# ADR-0026: Bronze→silver merge co-locates with ingestion (LP owns the merge for LP-ingested sources)

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted (implemented 2026-06-19 — M365 directory #239 + cloud_asset #241 merges shipped and wired into `Register-ImperionTask` #243; cloud ceded `cloud_asset` via Pipeline #135; M365-directory cede Pipeline #134 held until the LP entra-group collectors fill `m365_groups`/`m365_group_members` bronze in prod) |
| **Date** | 2026-06-18 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0010 (posture silver bulk merge — the precedent this generalizes) · ADR-0013 (Meta ingestion + merge) · pipeline ADR-0011 (live-data plane / merge-sources) · pipeline ADR-0012 (the merge runner) · frontend ADR-0042 (four-repo division of labour) |

<!-- | **Amends** | system CLAUDE.md §1 (Pipeline "bronze→silver merge" → live/webhook-driven only); pipeline CLAUDE.md §3 | (pending the sibling edits) -->

## Problem

The four-repo contract (frontend ADR-0042; system CLAUDE.md §1) assigned **all**
bronze→silver merge to the cloud Pipeline (`merge-sources`, every 5 min). In practice that
is already not true — this repo owns the **posture** (ADR-0010), **Meta** (ADR-0013), and
**DNS** (ADR-0008/`Invoke-ImperionDnsMerge`) merges, because it ingests those sources here
and merging them in the same scheduled run is simpler and avoids a cross-plane dependency.
But other LP-ingested sources still have their merge stranded in the cloud Pipeline:
**M365 directory groups** (`mergeDirectoryGroups`) and the **Azure ARM cloud assets**
(`mergeCloudAssetSources`) are collected here, yet merged there. That split means an
LP-fed source only reaches silver when the cloud's timer happens to run, couples LP
ingestion to a cloud deploy, and contradicts the doctrine that the heavy, scheduled,
compute-bound work lives on this node (§1).

## Context

- LP already INGESTS the M365 directory bronze (`scheduled-tasks/m365/entra-groups`,
  `entra-group-members`, `users` → `m365_groups` / `m365_group_members` / `m365_contacts`)
  and the Azure ARM bronze (`scheduled-tasks/azure/cloud-resources` → `cloud_resources`,
  ADR-0023). The collectors are here; only the merge is elsewhere.
- The established LP merge shape (ADR-0010 / ADR-0013 / DNS): an idempotent, set-based
  `Invoke-Imperion*Merge` cmdlet + a thin `.task.ps1` that runs it **after** the source's
  collectors, with a schema-gate try/catch.
- Webhook/live-driven merges genuinely belong in the cloud (a NAT'd home server cannot
  receive signed inbound traffic — §1): Autotask ticket webhooks, Graph change
  notifications, DocuSign Connect, the contact/account/device sweep fed by `website_*`
  manual edits via `POST /api/refresh`, Meta DM send.

## Options considered

1. **Leave all bulk-source merges in the cloud Pipeline** — keeps one merge home, but
   couples LP ingestion to a cloud deploy/cadence and contradicts §1; the posture/Meta/DNS
   merges already broke this rule for good reasons.
2. **Move every merge to LP** — over-rotates: webhook/live merges must stay on a public,
   always-on endpoint LP cannot provide (§1).
3. **Merge co-locates with ingestion (chosen)** — whichever plane ingests a source's
   bronze owns its bronze→silver merge. Bulk/scheduled sources merge here; live/webhook
   sources merge in the cloud.

## Decision

Adopt **merge-co-locates-with-ingestion** as the standing rule, generalizing ADR-0010
from posture to all LP-ingested sources:

- **LP owns the bronze→silver merge for every source LP bulk-ingests** — implemented as an
  idempotent, set-based `Invoke-Imperion*Merge` cmdlet run by a `.task.ps1` immediately
  after that source's collectors (the ADR-0010 / Meta / DNS shape).
- **The cloud Pipeline keeps only live/webhook-driven merges** — the contact/account/
  device/contract/ticket/opportunity/expense sweep fed by webhooks + `website_*` manual
  edits (`merge-sources` / `POST /api/refresh {source:'merge'}`), plus any future
  webhook-fed entity. It cedes the merges for sources it does not ingest.
- **First migration: M365 directory groups** (issue #239). `Invoke-ImperionM365DirectoryMerge`
  folds Entra group membership into the silver `contact_enrichment` `directory_groups`
  fact (front-end migration 0079; ported from `ImperionCRM_Pipeline`
  `src/shared/merge-directory.ts`). The cloud's `mergeDirectoryGroups` is ceded once this
  is verified in prod (Pipeline #134).
- **Second migration: Azure ARM cloud assets** (`cloud_resources` → `cloud_asset`) follows
  the same pattern once M365 proves out (sibling issues TBD; cedes the cloud's
  `mergeCloudAssetSources`).
- **Cutover is safe because both copies are idempotent.** The LP and cloud merges are both
  replace-from-source (delete-then-insert on the same `m365_directory` source label), so
  running both during cutover converges with no duplication — **the LP merge ships first**
  (additive), the cloud removal second (no gap).
- **The contact/account silver the directory merge enriches is still merged in the cloud.**
  This merge only reads `m365_contacts.contact_id` (set by the cloud contact sweep) and
  writes the `m365_directory` enrichment fact — a clean, independent source label. It
  degrades to "no candidates" until contacts are linked.

## Consequences

### Security impact

None new. Pure SQL over tables the LP Postgres role already reads/writes (front-end
migration 0079 grants); no Graph calls, no new scopes, no secrets. The `contact_enrichment`
provenance guardrail (CLAUDE.md §5) is preserved verbatim in SQL: every fact carries
`source = 'm365_directory'`, `lawful_basis = 'legitimate_interest'`, and a `collected_at`
provenance timestamp. Enrichment feeds the profile/ledger only — it never unlocks outbound
(the `current_consent` gate still governs). Per-tenant isolation holds: the group-name join
is keyed `(tenant_id, external_id)`, so names resolve within-tenant only.

### Cost impact

Neutral-to-positive: the merge moves off metered Azure Functions compute onto the on-prem
node (the §1 rationale). The cloud `merge-sources` timer does marginally less work once the
ceded merges are removed.

### Operational impact

- One new daily scheduled task (`Imperion m365 directory-merge`) registered via
  `Register-ImperionTask`, ordered after the directory collectors
  (`docs/operations/scheduled-task-registry.md`).
- The cloud Pipeline's `merge-sources` no longer owns M365 directory enrichment once
  Pipeline #134 lands — sequencing matters: **do not merge the cloud removal before the LP
  task is verified writing `contact_enrichment` in prod**, else the fact goes stale.
- System CLAUDE.md §1 and pipeline CLAUDE.md §3 wording need a small amendment (Pipeline =
  *live/webhook-driven* bronze→silver merge; LP += bulk-source bronze→silver merge) —
  proposed to Mark alongside this ADR; the §1 parent file is a governance edit, not a
  repo PR.

## Future considerations

- Azure ARM `cloud_asset` is the next migration under this ADR (cedes
  `mergeCloudAssetSources`); IT Glue silver, if/when it gains a dedicated merge, is a
  candidate too.
- If a source ever needs BOTH a webhook-driven live merge AND a bulk merge, split it (the
  §1 escape hatch): the cloud receiver lands a row, the LP task merges on cadence.

## Cross-references

ADR-0010 (the posture-merge precedent this generalizes) · ADR-0013 (Meta merge) ·
ADR-0008 (DNS golden/drift + `Invoke-ImperionDnsMerge`) · pipeline ADR-0011 (live-data
plane) · pipeline ADR-0012 (the merge runner being ceded from) · pipeline issue #134
(cede the M365 directory merge) · frontend ADR-0042 (four-repo division of labour) ·
frontend migration 0079 (m365_groups / m365_group_members).
