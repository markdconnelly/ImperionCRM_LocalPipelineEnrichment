# Integration — Entra / M365 group inventory (Graph /groups)

**Purpose.** Land the directory group inventory + membership per tenant in bronze (issues
#150 + #139; front-end migration 0079 / issue #257). Directory groups were entirely absent
before this — users already flow (`Get-ImperionM365User` → `m365_contacts` → silver
`contact`); this adds the groups themselves **and** the membership edges that connect a
group to its members.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post | Bronze table (frontend migration 0079) | Source |
| --- | --- | --- | --- | --- |
| Groups | `Get-ImperionM365Group` | `Set-ImperionM365GroupToBronze` | `m365_groups` | `m365` |
| Membership | `Get-ImperionM365GroupMember` | `Set-ImperionM365GroupMemberToBronze` | `m365_group_members` | `m365` |

**Groups.** One Graph enumeration per tenant covers every group (Microsoft 365, security,
mail-enabled security, dynamic). Standard envelope, PK `(tenant_id, source, external_id)`
with `external_id` = the **Entra group object id**, change-detected upsert via the
issue-#105 scaffold with the exact-0079 `-ColumnSet` projection (future collector fields
drop from the flat projection but survive in `raw_payload`). Flat columns are all-text per
the bronze contract — booleans land `'true'`/`'false'`, `groupTypes` joins to delimited
text, dates re-serialize ISO 8601.

**Membership.** `Get-ImperionM365GroupMember` enumerates group ids, then expands each
group's direct members (`/groups/{id}/members`) into one EDGE row per membership. A
membership has no natural id, so `external_id` is the collector-built
`<group id>/<member id>` composite (the 0078 composite-id precedent). The flat parts carry
the join keys: `group_external_id` = the parent group object id; `member_external_id` = the
member directory object id, which equals **`m365_contacts.external_ref` = the Entra user
object id** — how a membership reaches the silver contact (the front-end Directory-groups
surface, #257). `member_type` is the Graph `@odata.type`, so non-user members (nested
groups, devices, service principals) are retained and distinguishable; only user members
resolve to a contact.

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`,
ADR-0002 cert custody; per-client Onboarding app model per pipeline ADR-0018 amendment),
single-tenant against the Imperion company tenant by default; fan-out via
`IMPERION_M365_TENANT_IDS`. Application permissions **Group.Read.All** (groups) +
**GroupMember.Read.All** (membership) — read-only, no new write grant.

## Endpoints, paging, $select
- `GET /v1.0/groups?$select=…` — the group enumeration; paging follows `@odata.nextLink`
  (`Invoke-ImperionGraphRequest`); 429/Retry-After handled by the shared retry core. The
  **`$select` is required**: `membershipRule`, `membershipRuleProcessingState`, and
  `isAssignableToRole` are NOT in the default `/groups` projection — without selecting them
  the dynamic-group columns would land NULL even when set.
- `GET /v1.0/groups/{id}/members?$select=id,displayName,userPrincipalName,mail` — one call
  per group (the membership getter enumerates `/groups?$select=id` first). `@odata.type` is
  always returned for directoryObject collections, so member kind survives regardless of
  `$select`. Member expansion is **direct members only** (no transitive flatten — nested
  groups are retained as edges, not recursed).
- Bronze over-collects: the full group/member record is lossless in `raw_payload`; flat
  columns are the queryable subset.

## Cadence & gates (scheduled-tasks/README.md)
`m365/entra-groups` + `m365/entra-group-members` **daily** (both slow-changing). Gates
(fail soft — the task's catch logs Warn + exits clean):
1. **Migration 0079 prod apply** — applied 2026-06-12 (`m365_groups` / `m365_group_members`
   exist with the `imperion-localpipeline` grants). No local-pipeline change needed.
2. Task **registration** itself is deferred to server bringup (#102).

## Provenance & PII posture
Rows are stamped source/collected_at per the envelope. Group display names / mail
addresses are client business metadata — never log row content (counts/durations only).
Data feeds the contact Directory-groups surface (front-end #257) via the membership edges,
never outreach.
