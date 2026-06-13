# Integration — Defender XDR incidents + alerts (Graph security API)

**Purpose.** Land the Defender XDR incident/alert stream in bronze so security incidents
layer with Autotask tickets per incident (issue #138; front-end migration 0076 / ADR-0059;
Mark's 2026-06-12 per-source verdict). The existing `sentinel` source (issue #97) covers
Azure Sentinel rules/watchlists/workbooks via ARM ONLY — this is the net-new Graph
incident/alert feed.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post (multi-table router) | Bronze table (frontend migration 0076) | Source |
| --- | --- | --- | --- | --- |
| Incidents | `Get-ImperionDefenderObject` | `Set-ImperionDefenderToBronze` | `defender_incidents` | `defender` |
| Alerts | `Get-ImperionDefenderObject` | `Set-ImperionDefenderToBronze` | `defender_alerts` | `defender` |

One get covers both entities (`entity` discriminator, the sentinel pattern); the post
projects each row to its table's exact 0076 column set. Standard envelope, PK
`(tenant_id, source, external_id)` with `external_id` = the Graph id, change-detected
upsert via the issue-#105 scaffold.

**Layering keys (ADR-0059).** `defender_alerts.incident_external_id` (Graph `incidentId`)
groups alerts under their incident (indexed `tenant_id, incident_external_id`). The
incident↔Autotask pairing table `defender_incident_ticket_link` is **NOT written by this
collector** — it lives outside bronze and belongs to the linking flows (PK
`tenant_id, incident_external_id` = the one-ticket-per-incident idempotency key).

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`,
ADR-0002 cert custody), single-tenant against the Imperion company tenant by default;
fan-out via `IMPERION_M365_TENANT_IDS`. Application permissions
**SecurityIncident.Read.All + SecurityAlert.Read.All** — already admin-consented on the
app; read-only, no new write grant.

## Endpoints, paging, rate limits
- `GET /v1.0/security/incidents` and `GET /v1.0/security/alerts_v2`; paging follows
  `@odata.nextLink` (`Invoke-ImperionGraphRequest`); 429/Retry-After handled by the
  shared retry core. Microsoft caps the security API around 50 calls/min per app/tenant —
  the hourly cadence is far inside it.
- Bronze over-collects: full payload lossless in `raw_payload` (incl. `evidence` on
  alerts, which is never flattened); flat columns are the queryable subset only.

## Cadence & gates (scheduled-tasks/README.md)
`m365/defender` **hourly**. Gates (fail soft — the task's catch logs Warn + exits clean):
1. **Migration 0076 prod apply** — until the tables exist, the upsert fails loudly and
   the task gates. No local-pipeline change needed after apply.
2. Task **registration** itself is deferred to server bringup (#102).

## Provenance & PII posture
Rows are stamped source/collected_at per the envelope. Incident/alert payloads can carry
user/device identifiers (assignedTo, evidence in raw_payload) — never log row content;
data feeds the security view + per-incident ticket layering only.
