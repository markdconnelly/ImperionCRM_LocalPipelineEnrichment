# Integration — Entra / M365 group inventory (Graph /groups)

**Purpose.** Land the directory group inventory per tenant in bronze (issue #150, split
from #139; front-end migration 0079 / issue #257). Directory groups were entirely absent
before this — users already flow (`Get-ImperionM365User` → `m365_contacts` → silver
`contact`); this adds the groups themselves. The **membership edges** that connect a group
to its members are a **separate collector** (`entra-group-members`, issue #139); this feed
is the group objects only.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post | Bronze table (frontend migration 0079) | Source |
| --- | --- | --- | --- | --- |
| Groups | `Get-ImperionM365Group` | `Set-ImperionM365GroupToBronze` | `m365_groups` | `m365` |

One Graph enumeration per tenant covers every group (Microsoft 365, security, mail-enabled
security, dynamic). Standard envelope, PK `(tenant_id, source, external_id)` with
`external_id` = the **Entra group object id**, change-detected upsert via the issue-#105
scaffold with the exact-0079 `-ColumnSet` projection (future collector fields drop from the
flat projection but survive in `raw_payload`). Flat columns are all-text per the bronze
contract — booleans land `'true'`/`'false'`, `groupTypes` joins to delimited text, dates
re-serialize ISO 8601.

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`,
ADR-0002 cert custody; per-client Onboarding app model per pipeline ADR-0018 amendment),
single-tenant against the Imperion company tenant by default; fan-out via
`IMPERION_M365_TENANT_IDS`. Application permission **Group.Read.All** — read-only, no new
write grant.

## Endpoints, paging, $select
- `GET /v1.0/groups?$select=…` — the group enumeration; paging follows `@odata.nextLink`
  (`Invoke-ImperionGraphRequest`); 429/Retry-After handled by the shared retry core. The
  **`$select` is required**: `membershipRule`, `membershipRuleProcessingState`, and
  `isAssignableToRole` are NOT in the default `/groups` projection — without selecting them
  the dynamic-group columns would land NULL even when set.
- Bronze over-collects: the full group record is lossless in `raw_payload`; flat columns
  are the queryable subset (display name, mail nickname/address, description, group types,
  security/mail-enabled flags, visibility, classification, role-assignable flag, dynamic
  membership rule + processing state, on-prem sync flag, created/renewed/expiration dates).

## Cadence & gates (scheduled-tasks/README.md)
`m365/entra-groups` **daily** (group inventory is slow-changing). Gates (fail soft — the
task's catch logs Warn + exits clean):
1. **Migration 0079 prod apply** — applied 2026-06-12 (`m365_groups` exists with the
   `imperion-localpipeline` grants). No local-pipeline change needed.
2. Task **registration** itself is deferred to server bringup (#102).

## Provenance & PII posture
Rows are stamped source/collected_at per the envelope. Group display names / mail
addresses are client business metadata — never log row content (counts/durations only).
Data feeds the contact Directory-groups surface (front-end #257) via the membership edges,
never outreach.
