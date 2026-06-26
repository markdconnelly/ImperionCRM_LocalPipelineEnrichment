# Integration — Information protection (sensitivity labels · custom security attribute definitions)

**Purpose.** Capture a tenant's **data-classification taxonomy** so the front-end can
benchmark it against a golden standard: Microsoft Purview **sensitivity labels** and Entra
**custom security attribute definitions**. Read-only Graph; flatten → bronze; no IT Glue
write (these are directory/security-config objects, not the operational/infrastructure data
the IT Glue hub documents — CLAUDE.md §6). Issue #141; front-end schema + benchmark issue
ImperionCRM#575 (the applied bronze tables; the earlier #259 framing is superseded).

> **Benchmark runs in the front end, not here.** The compliant / drift / ungoverned /
> missing classification against a golden baseline runs in the front-end posture merge per
> the golden-baseline pattern (CLAUDE.md §5; issue #575). This repo only lands the taxonomy
> flat to bronze.

> **Definitions, not assignments.** This collector ingests custom security attribute
> *definitions* (the tenant's attribute taxonomy + allowed values). Per-principal
> *assignments* (the key=value tags on individual users/SPs) are a heavier, principal-joined,
> **PII-bearing** surface and are **deferred** to a follow-up (scope
> `CustomSecAttributeAssignment.Read.All`, endpoint `/users/{id}?$select=customSecurityAttributes`)
> — see *Deferred* below.

## Auth
- **Cert-based app-only** token (`Get-MsalToken -ClientCertificate`) for Microsoft Graph,
  scope `https://graph.microsoft.com/.default`. Same cert SP as every other Graph collector.
- **Graph application permissions required (read-only):**
  - `SensitivityLabels.Read.All` — `/beta/security/informationProtection/sensitivityLabels`
  - `CustomSecAttributeDefinition.Read.All` — `/directory/customSecurityAttributeDefinitions`
  - Both are part of the **read-only-by-default** grant (ADR-0002); neither is a write or
    data-plane grant. Adding/consenting them is a human-approval gate (CLAUDE.md §8).
  - **Note (custom security attributes):** reading attribute definitions requires the caller
    to hold the **Attribute Definition Reader** directory role *in addition to* the app
    permission — custom security attributes are access-gated beyond the scope grant. Confirm
    on first live run.
- **Tenant scope:** Imperion's own tenant by default. Client tenants fan out via the
  per-client onboarding app (`IMPERION_M365_TENANT_IDS`, CLAUDE.md §3); each row is
  stamped with its owning tenant (per-tenant isolation).

## Source endpoints (paged via `@odata.nextLink`)
| Object | Endpoint | Notes |
| --- | --- | --- |
| Sensitivity labels | `GET /beta/security/informationProtection/sensitivityLabels` | `id` = label GUID; **beta-only** (`/v1.0` 400s 'segment informationProtection not found') |
| Custom security attribute definitions | `GET /v1.0/directory/customSecurityAttributeDefinitions?$expand=allowedValues` | `id` = `{attributeSet}_{name}`; `$expand` carries the predefined value list (lands in `raw_payload`) |

## Flattened fields (the classification taxonomy)
The flat columns are exactly the applied #575 bronze columns; everything else stays lossless
in `raw_payload`.
- **Sensitivity labels** → `label_id` (= Graph `id`) · `name` · `priority` (= Graph
  `sensitivity` ordering) · `is_active`. *Lossless in `raw_payload`:* description, tooltip,
  applies-to, rights, auto-labelling, the full sublabel tree. *Benchmark reads:* published
  label set, active vs. inactive, ordering.
- **Custom security attribute definitions** → `attribute_set` · `name` · `data_type`
  (= Graph `type`) · `status` (Available / Deprecated). *Lossless in `raw_payload`:*
  description, collection / searchable / predefined-only flags, the allowed-value list.
  *Benchmark reads:* expected attribute sets/attributes present, deprecated attributes.

Bronze flat columns are all-text (booleans → `'true'`/`'false'`); the full lossless objects
live in `raw_payload` (CLAUDE.md §4/§6).

## Postgres targets (bronze — standard envelope)
`m365_sensitivity_labels` · `entra_custom_security_attributes` (logical source `m365`) —
flattened columns + `tenant_id`, `source`, `external_id`, `content_hash`, `collected_at`,
`raw_payload (jsonb)`. Upsert on `(tenant_id, source, external_id)`, change-detected.
`external_id` = label GUID / `{attributeSet}_{name}` respectively. **Schema is owned by the
front end** (ImperionCRM#575, **already prod-applied**) — this repo never creates the tables;
the post fails loudly if a table/column is absent (deploy-ahead safe).

## Cmdlets
- Get layer (collect → flatten, no write): `Get-ImperionSensitivityLabel` ·
  `Get-ImperionCustomSecurityAttribute`.
- Post layer (write flat rows → bronze, change-detected): `Set-ImperionSensitivityLabelToBronze`
  · `Set-ImperionCustomSecurityAttributeToBronze`.
- Scheduled-task files: `scheduled-tasks/m365/sensitivity-labels.task.ps1` ·
  `custom-security-attributes.task.ps1` (daily; see the scheduled-task registry).

## Rate limits & retry
Graph throttles per-tenant; honor `Retry-After` on 429 with exponential backoff (handled by
`Invoke-ImperionRestWithRetry`). Page politely. Log record counts + duration per run.

## Provenance & PII
Source `m365`, `collected_at` stamped on every row. Sensitivity labels and attribute
*definitions* are tenant-config metadata — **no per-user PII**. The deferred *assignment*
collector would read principal-level data and must carry the lawful-basis / provenance
guardrail (CLAUDE.md §8) before it is built.

## Assumptions to confirm on first live run
- The onboarding app has `SensitivityLabels.Read.All` and `CustomSecAttributeDefinition.Read.All`
  admin-consented in Imperion's own tenant (and per client tenant for client fan-out), plus
  the **Attribute Definition Reader** role for the custom-security-attribute read.
- The front-end `m365_sensitivity_labels` / `entra_custom_security_attributes` bronze tables
  (ImperionCRM#575) are applied to prod (confirmed) and the local-pipeline SP has the write
  grant on them.
- Live run is gated on the on-prem host running the collectors; deploy-ahead is safe (the post
  fails loudly only if a table/column is missing).

## Deferred (follow-up)
- **Custom security attribute ASSIGNMENTS** — per-principal `customSecurityAttributes` (scope
  `CustomSecAttributeAssignment.Read.All`). Principal-joined and PII-bearing; needs its own
  collector + a front-end migration + the lawful-basis guardrail. Filed as a follow-up
  (see issue #141 thread).
