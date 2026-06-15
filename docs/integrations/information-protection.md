# Integration — Information protection (sensitivity labels · custom security attribute definitions)

**Purpose.** Capture a tenant's **data-classification taxonomy** so the front-end can
benchmark it against a golden standard: Microsoft Purview **sensitivity labels** and Entra
**custom security attribute definitions**. Read-only Graph; flatten → bronze; no IT Glue
write (these are directory/security-config objects, not the operational/infrastructure data
the IT Glue hub documents — CLAUDE.md §6). Issue #141; front-end schema + benchmark issue
ImperionCRM#259.

> **Benchmark runs in the front end, not here.** The compliant / drift / ungoverned /
> missing classification against a golden baseline runs in the front-end posture merge per
> the golden-baseline pattern (CLAUDE.md §5; issue #259). This repo only lands the taxonomy
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
  - `SensitivityLabels.Read.All` — `/security/informationProtection/sensitivityLabels`
  - `CustomSecAttributeDefinition.Read.All` — `/directory/customSecurityAttributeDefinitions`
  - Both are part of the **read-only-by-default** grant (ADR-0002); neither is a write or
    data-plane grant. Adding/consenting them is a human-approval gate (CLAUDE.md §8).
  - **Note (custom security attributes):** reading attribute definitions requires the caller
    to hold the **Attribute Definition Reader** directory role *in addition to* the app
    permission — custom security attributes are access-gated beyond the scope grant. Confirm
    on first live run.
- **Tenant scope:** the **partner tenant** by default. Customer tenants fan out over GDAP via
  `IMPERION_M365_TENANT_IDS` (CLAUDE.md §3); each row is stamped with its owning tenant
  (per-tenant isolation).

## Source endpoints (paged via `@odata.nextLink`)
| Object | Endpoint | Notes |
| --- | --- | --- |
| Sensitivity labels | `GET /v1.0/security/informationProtection/sensitivityLabels` | `id` = label GUID; labels nest (sublabels) via `parent` |
| Custom security attribute definitions | `GET /v1.0/directory/customSecurityAttributeDefinitions?$expand=allowedValues` | `id` = `{attributeSet}_{name}`; `$expand` carries the predefined value list |

## Flattened fields (the classification taxonomy)
- **Sensitivity labels** → `label_name` · `display_name` · `description` · `is_active` ·
  `is_appendable` · `sensitivity` (ordering priority) · `tooltip` · `applies_to` ·
  `parent_label_id` + `parent_label_name` (sublabel nesting). *Benchmark reads:* published
  label set, active vs. inactive, expected taxonomy coverage.
- **Custom security attribute definitions** → `attribute_set` · `attribute_name` ·
  `description` · `type` · `status` (Available / Deprecated) · `is_collection` ·
  `is_searchable` · `use_predefined_values_only` · `allowed_values` (joined active values).
  *Benchmark reads:* expected attribute sets/attributes present, deprecated attributes,
  free-form vs. governed value lists.

Bronze flat columns are all-text (booleans → `'true'`/`'false'`, collections → delimited);
the full lossless objects — rights, auto-labelling, the full sublabel tree, the complete
allowed-value list — live in `raw_payload` (CLAUDE.md §4/§6).

## Postgres targets (bronze — standard envelope)
`sensitivity_labels` · `custom_security_attribute_definitions` (logical source `m365`) —
flattened columns + `tenant_id`, `source`, `external_id`, `content_hash`, `collected_at`,
`raw_payload (jsonb)`. Upsert on `(tenant_id, source, external_id)`, change-detected.
`external_id` = label GUID / `{attributeSet}_{name}` respectively. **Schema is owned by the
front end** (ImperionCRM#259) — this repo never creates the tables; the post fails loudly
until the migration is applied to prod (deploy-ahead safe).

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
- The cert app has `SensitivityLabels.Read.All` and `CustomSecAttributeDefinition.Read.All`
  consented in the partner tenant (and via GDAP for customer tenants), plus the **Attribute
  Definition Reader** role for the custom-security-attribute read.
- The front-end `sensitivity_labels` / `custom_security_attribute_definitions` bronze
  migration (ImperionCRM#259) is applied to prod and the local-pipeline SP has the write
  grant on them (follow-up grant migration, same as the 0036/0079 tables).
- Live run is gated on the on-prem host coming online (#102); deploy-ahead is safe (the post
  self-gates and exits cleanly until the schema lands).

## Deferred (follow-up)
- **Custom security attribute ASSIGNMENTS** — per-principal `customSecurityAttributes` (scope
  `CustomSecAttributeAssignment.Read.All`). Principal-joined and PII-bearing; needs its own
  collector + a front-end migration + the lawful-basis guardrail. Filed as a follow-up
  (see issue #141 thread).
