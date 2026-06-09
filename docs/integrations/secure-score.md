# Integration — Microsoft Secure Score

**Purpose.** Poll Microsoft Secure Score into Postgres bronze: the overall daily score
snapshots and the control-level attributes (the "secure score attributes"). Read-only;
feeds the agent's posture awareness. Cmdlet: `Invoke-ImperionSecureScoreSync`.

## Auth
- Cert app-only Graph token; scope `https://graph.microsoft.com/.default`.
- **Permission:** `SecurityEvents.Read.All` (application, read-only).
- Partner tenant by default; customer tenants via GDAP.

## Source endpoints (Graph v1.0)
| Object | Endpoint |
| --- | --- |
| Overall score snapshots | `GET /security/secureScores` (per-day, with `controlScores[]` breakdown in the payload) |
| Control attributes | `GET /security/secureScoreControlProfiles` |

## Flattened fields
- **secure_scores:** `current_score`, `max_score`, `active_user_count`,
  `licensed_user_count`, `enabled_services`, `created_date_time`, `azure_tenant_id`
  (per-control breakdown stays in `raw_payload`).
- **secure_score_control_profiles:** `control_name`, `control_category`, `title`,
  `max_score`, `rank`, `service`, `action_type`, `user_impact`, `implementation_cost`,
  `tier`, `threats`, `remediation`, `deprecated`.

## Change detection
Each daily snapshot has a unique id → inserts as a new row (history). Control profiles are
hash-compared; unchanged → skipped. Bronze tables `secure_scores` /
`secure_score_control_profiles` (`sql/security_posture_schema.sql`).

## Assumptions to confirm
- `SecurityEvents.Read.All` consented for the cert app.
- Whether per-control daily breakdown should be expanded into its own table later (kept in
  `raw_payload` for now).
