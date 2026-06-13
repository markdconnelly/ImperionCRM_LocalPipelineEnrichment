# Integration — Entra auth methods / per-user MFA registration (Graph reports API)

**Purpose.** Land every user's authentication-method registration state in bronze so MFA
posture is visible on the company asset (issue #140; front-end migration 0077 / ADR-0051;
Mark's 2026-06-12 per-source verdict). Domain was entirely absent before this — no other
bronze covers per-user MFA/SSPR registration (Intune covers devices, CA policies cover
tenant config; this is the per-user identity-protection truth).

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post | Bronze table (frontend migration 0077) | Source |
| --- | --- | --- | --- | --- |
| User registration details | `Get-ImperionEntraAuthMethod` | `Set-ImperionEntraAuthMethodToBronze` | `entra_auth_methods` | `m365` |

One Graph call per tenant covers every user (the report endpoint, not N per-user method
reads). Standard envelope, PK `(tenant_id, source, external_id)` with `external_id` = the
**Entra user object id**, change-detected upsert via the issue-#105 scaffold with the
exact-0077 `-ColumnSet` projection (future collector fields drop from the flat projection
but survive in `raw_payload`). Flat columns are all-text per the bronze contract —
booleans land `'true'`/`'false'`, collections (`methods_registered`,
`system_preferred_authentication_methods`) join to `; `-delimited text.

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`,
ADR-0002 cert custody; per-client app model per pipeline ADR-0018), single-tenant against
the Imperion company tenant by default; fan-out via `IMPERION_M365_TENANT_IDS`.
Application permission **UserAuthenticationMethod.Read.All** — already admin-consented on
the Onboarding app; read-only, no new write grant.

## Endpoints, paging, rate limits
- `GET /v1.0/reports/authenticationMethods/userRegistrationDetails`; paging follows
  `@odata.nextLink` (`Invoke-ImperionGraphRequest`); 429/Retry-After handled by the
  shared retry core. One collection call per tenant — trivially inside Graph's reports
  throttling budget at the daily cadence.
- Bronze over-collects: full report record lossless in `raw_payload`; flat columns are
  the queryable subset (isMfaRegistered / isMfaCapable / SSPR state / methodsRegistered /
  preferred methods / lastUpdatedDateTime).

## Cadence & gates (scheduled-tasks/README.md)
`m365/auth-methods` **daily** (registration state is slow-changing). Gates (fail soft —
the task's catch logs Warn + exits clean):
1. **Migration 0077 prod apply** — until `entra_auth_methods` exists with the
   `imperion-localpipeline` grants, the upsert fails loudly and the task gates. No
   local-pipeline change needed after apply.
2. Task **registration** itself is deferred to server bringup (#102).

## Provenance & PII posture
Rows are stamped source/collected_at per the envelope. Records identify users by UPN /
display name / object id and reveal their MFA posture — security-sensitive PII: never log
row content (counts/durations only); data feeds the security/posture view on the company
asset, never outreach.
