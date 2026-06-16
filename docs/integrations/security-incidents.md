# Integration — Microsoft security incidents + alerts + evidence (Graph security API)

**Purpose.** Land the Microsoft security-incident picture in bronze as a three-tier
security-fidelity payload (incident → alerts → evidence), correlated to its Autotask ticket,
so silver can stitch the Microsoft view (rich-but-ephemeral) and the Autotask view
(durable system of record) into ONE normalized incident timeline (issue #196, **ADR-0019**;
front-end migration **0119**; epic #194).

This is **net-new** and **distinct from `defender-xdr.md`** (the older `defender_incidents` /
`defender_alerts` set, migration 0076 / ADR-0059): that one has no evidence grain and no
Autotask correlation key. This collector lands `m365_incidents` / `m365_alerts` /
`m365_evidence` (the `m365` source, ADR-0019 §1) — the full incident/alert/evidence tree plus
`autotask_ticket_ref`. The two coexist by design; silver narrows + dedupes downstream.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post (multi-table router) | Bronze table (FE migration 0119) | Source |
| --- | --- | --- | --- | --- |
| Incidents | `Get-ImperionSecurityIncident` | `Set-ImperionSecurityIncidentToBronze` | `m365_incidents` | `m365` |
| Alerts | `Get-ImperionSecurityIncident` | `Set-ImperionSecurityIncidentToBronze` | `m365_alerts` | `m365` |
| Evidence | `Get-ImperionSecurityIncident` | `Set-ImperionSecurityIncidentToBronze` | `m365_evidence` | `m365` |

One get covers all three entities via the `entity` discriminator (the Defender/Sentinel
pattern); the post projects each row to its table's exact 0119 column set and drops the
discriminator + any extra collector field (those survive in `raw_payload`). Standard envelope,
PK `(tenant_id, source, external_id)`, change-detected upsert via the issue-#105 scaffold.
Security incidents are operational telemetry, not operational-config data, so they flatten
**straight to Postgres** — the IT Glue documentation step is skipped (ADR-0006 / ADR-0019 §1).

**Parent→child linkage (ADR-0019 §1)** is carried in the FE-provisioned FK columns:
`m365_alerts.incident_id` → `m365_incidents.incident_id`, and
`m365_evidence.alert_id` → `m365_alerts.alert_id`. Evidence items often lack a stable Graph id,
so the collector synthesizes `external_id = "<alertId>::<ordinal>"` for a stable upsert key
(the real id, if any, survives in `raw_payload`).

## Autotask correlation — `autotask_ticket_ref` (CONFIRM-BEFORE-LIVE GATE)
Autotask is the **durable system of record** for incident history (ADR-0019 §1); the Microsoft
tables are a recent-fidelity overlay. The link is `m365_incidents.autotask_ticket_ref`.

> **OPEN ITEM — confirm the `autotask_ticket_ref` format BEFORE wiring the silver stitch.**
> Microsoft Graph does **not** natively expose an Autotask ticket field. The ref is expected to
> ride a tag written by the MS↔Autotask sync connector (`customTags` / `systemTags`), but the
> **exact format is UNCONFIRMED** — ticket number vs id/GUID vs URL vs connector tag — and so is
> *which* tag carries it and how reliably it is populated. Per ADR-0019 the collector **never
> invents or transforms** the value: it captures the **raw** candidate (first non-empty of
> `-AutotaskRefCandidatePath`, default `customTags` then `systemTags`; the full tag set is always
> in `raw_payload`) and leaves it untouched. **Confirm against real `m365_incidents` rows + the
> live Autotask ticket shape, then repoint `-AutotaskRefCandidatePath` to the confirmed carrier,
> before the silver join is built** (same posture as the MileIQ / Datto live-shape confirmations,
> ADR-0017 / ADR-0018). The reciprocal Autotask→MS ref is verified at the same time. Silver
> stitches MS + Autotask later — NOT in this collector.

## Auth — read-only Graph via the per-client onboarding app (CLAUDE.md §3, pipeline ADR-0018)
`Get-ImperionGraphToken` mints the cert-SP app-only token in the target tenant — the per-client,
admin-consented **onboarding app**, NOT GDAP (#196 phrases it "GDAP read-only"; that maps to the
onboarding-app model, ADR-0019 §Context). Application permissions
**SecurityIncident.Read.All + SecurityAlert.Read.All** (read-only; already the Defender
collector's grant — no net-new grant). Single-tenant against the Imperion company tenant by
default; fan-out via `IMPERION_M365_TENANT_IDS`. **Per-tenant isolation is absolute** — every row
is stamped with its owning tenant; an unconsented tenant is never reached (fail closed). **No
secret values** are ever in code/logs/tests/commits — names only (CLAUDE.md §2).

## Endpoints, paging, rate limits
- `GET /v1.0/security/incidents?$expand=alerts`; each alert's `evidence[]` rides on the expanded
  alert. Paging follows `@odata.nextLink` (`Invoke-ImperionGraphRequest`); 429/Retry-After handled
  by the shared retry core. Microsoft caps the security API ~50 calls/min per app/tenant — the
  hourly cadence is far inside it.
- Bronze over-collects: the full incident/alert/evidence payload is lossless in `raw_payload`
  (MITRE techniques, detection source, entity verdicts, remediation status, all tags); flat columns
  are the queryable subset migration 0119 defines.

## Cadence, gates & DORMANT status (scheduled-tasks/README.md)
`scheduled-tasks/security/incidents.task.ps1` — **hourly**. Gates (fail soft — the task's catch
logs `Warn` + exits clean so the schedule never crashes):
1. **Schema gate: CLEAR.** FE migration 0119 (`m365_incidents` / `m365_alerts` / `m365_evidence`)
   is SHIPPED + prod-applied.
2. **Onboarding-app consent** for the target tenant — until consented, the post fails loudly + gates.
3. **Task registration** is deferred to server bringup (#102).
4. **CONFIRM-BEFORE-LIVE:** the `autotask_ticket_ref` carrier (above) before the silver stitch.

**DORMANT until creds provisioned (#102) + the `autotask_ticket_ref` format confirmed.**

## Retention (ADR-0019 §3)
`m365_incidents` / `m365_alerts` / `m365_evidence` are capped at **180 days** by
`Invoke-ImperionSecurityRetentionSweep` (security tables ONLY) — see
[`../operations/scheduled-task-registry.md`](../operations/scheduled-task-registry.md). Safe because
Autotask holds the durable history; bounding the window also shrinks the standing PII surface.

## Silver consequence (front-end OKF, system CLAUDE.md §11)
Stitching MS + Autotask into one normalized **incident** timeline (Autotask = source of record) is
a silver-entity shape / source-of-record decision owned by the front end — propose the OKF concept
file + `coverage-matrix.md` row back as a front-end issue at this phase (ADR-0019 §Operational).

## Provenance & PII posture
Rows are stamped `source` / `collected_at` per the envelope. Incident/alert/evidence payloads can
carry sensitive entity detail (hostnames, user identifiers, IPs in evidence) — **never log row
content**; the 180-day bound is itself a PII control. Data feeds the security incident view +
per-incident ticket correlation only.
