# Front-end schema handoff — migrations this repo needs

The front-end repo (`ImperionCRM`) **owns the database schema and all migrations**
(front-end ADR-0017 / this repo ADR-0005). This local module **reads and writes** the
shared PostgreSQL but never runs DDL. This doc is the **migration request**: everything the
front-end repo must add before the module's cmdlets can land data. Ready-to-apply DDL lives
in this repo's [`/sql`](../../sql/) — copy it into a front-end `db/migrations` file.

## Status (2026-06-09)
The table migrations below are **authored in the front-end repo** as `db/migrations/0038`–`0043`
(`0038_local_pipeline_bronze`, `0039_related_bronze_views`, `0042_darkwebid_provider`,
`0043_security_ingestion`). The `/sql` files in this repo remain the source-of-record DDL they
were copied from.
1. **`0038`–`0043` are CONFIRMED APPLIED in prod** (verified 2026-06-09 against
   `imperioncrm-pg-prd`): every target table, the related-bronze + exposure views, and the
   `connection_provider` enum value `darkwebid` are present. **No action needed.**
2. **Grant the pipeline SP** — front-end `db/migrations/0044_local_pipeline_grants.sql` is
   **authored (proposed) and NOT applied**: least-privilege `SELECT, INSERT, UPDATE` (no DELETE,
   no blanket `ALL TABLES`) on exactly the bronze/golden tables this repo writes. **Blocked:** it
   needs the pipeline SP's real Postgres role name + Entra object id (the unattended identity is
   **not yet provisioned on the server** — no `%ProgramData%\Imperion\`, no filled
   `pipeline.config.psd1`), plus the one-time `pgaadauth` role bootstrap. **§8 approval gate**
   (a new write-capable DB principal). See its header.
3. **Prove the live chain** once the cert/gMSA/SecretStore + SP role exist:
   `build/Test-ImperionUnattendedChain.ps1` (cert → token → Postgres → rolled-back throwaway
   write). It cannot pass until the unattended identity is provisioned (CLAUDE.md §10 step 2).

## How to apply (for net-new tables added later)
1. Create a new front-end migration (next number after the latest — the dir is at `0044`).
2. Paste the DDL from the `/sql` files below (in this order).
3. Apply with the committed runner: `node C:/Development/GitHub/ImperionCRM/scripts/migrate.mjs <n>`.
4. Add the new tables to `0044`'s grant list (or a follow-on grant migration) so the pipeline
   SP can write them (ADR-0003 — the role is scoped to exactly the tables this repo touches).

## Conventions (apply to every table below)
- **Naming:** `{source}_{entity}` (e.g. `autotask_contracts`, `itglue_organizations`) —
  consistent with the existing per-source bronze convention (front-end ADR-0039 / pipeline
  ADR-0009). The catalog's `_bronze`-suffixed names in `CLAUDE.md §5` are *logical* keys.
- **Bronze is lossless/raw → flat columns are `text`.** The loader coerces every value to a
  stable string (dates to ISO 8601); true types live in `raw_payload jsonb`. **Silver does
  the casting.** This deliberately avoids type-mismatch fragility (PowerShell auto-converts
  ISO date strings to `[datetime]`).
- **Envelope on every bronze table:** `tenant_id, source, external_id, collected_at,
  raw_payload jsonb, content_hash`, `PRIMARY KEY (tenant_id, source, external_id)`
  (IT Glue tables key on `(source, external_id)`).
- **Change detection** relies on `content_hash` + the conflict key — keep the PK as written.

## 1. Already exist — reconcile, do not duplicate
- `autotask_companies`, `autotask_contacts`, and the per-source company/contact/device bronze
  tables from the cloud Pipeline (front-end ADR-0039 / pipeline ADR-0009). This module does
  **not** write companies/contacts today (the cloud Pipeline owns them). DDL for
  `autotask_companies`/`autotask_contacts` is included in `kaseya_bronze_schema.sql` **for
  reference only** — reconcile column names; don't re-create if they already exist.

## 2. New tables to add (by source file)

### a. IT Glue export — [`sql/itglue_bronze_schema.sql`](../../sql/itglue_bronze_schema.sql)
- 13 per-type tables **`itglue_export_{organizations, configurations, contacts, locations,
  flexible_asset_types, flexible_assets, domains, manufacturers, models, operating_systems,
  configuration_types, organization_types, organization_statuses}`** — generic envelope +
  `organization_id, name, resource_url, created_at, updated_at`. **Verified against the live
  US IT Glue API.** (`documents` and `configuration_interfaces` are nested, not top-level
  collections — excluded.)
- **`itglue_export_*` is namespaced** to avoid colliding with the existing per-source bronze
  `itglue_contacts` / `itglue_companies` / `itglue_devices` from front-end migration 0036
  (those are IT Glue *as a source of contacts/companies/devices*; the export is the full IT
  Glue *documentation graph* — a different dataset).
- `itglue_export_relationship` — the **polymorphic many-to-many edge table**
  (`from_type, from_id, to_type, to_id, relationship_name`) for IT Glue's open relationship
  types (ADR-0006). Indexed both directions.

### b. Azure + Sentinel + Entra SPs — [`sql/azure_inventory_schema.sql`](../../sql/azure_inventory_schema.sql)
- `m365_service_principals`; `azure_management_groups`, `azure_subscriptions`,
  `azure_resource_groups`, `azure_resources`; `sentinel_analytic_rules`,
  `sentinel_automation_rules`, `sentinel_watchlists`, `sentinel_workbooks`.

### c. Kaseya stack — [`sql/kaseya_bronze_schema.sql`](../../sql/kaseya_bronze_schema.sql)
- `autotask_contracts`, `autotask_tickets` — **columns confirmed against the live Autotask
  field-metadata API** (note: Autotask keys companies via `companyID`; contracts sync on
  `lastModifiedDateTime`, tickets on `lastActivityDate`).
- `kqm_proposals`, `website_proposals`, `docusign_contracts` — columns are **assumptions**
  (no live access yet); confirm on first pull.

### d. Security posture (Secure Score + golden states) — [`sql/security_posture_schema.sql`](../../sql/security_posture_schema.sql)
- `secure_scores`, `secure_score_control_profiles`.
- Observed policy bronze: `entra_conditional_access_policies`, `intune_security_policies`,
  `device_configuration_policies`, `autopilot_policies`, `defender_xdr_security_policies`.
- **Golden-state** tables (approved baselines, keyed `(tenant_id, policy_id)`):
  `conditional_access_policies_golden`, `intune_security_policies_golden`,
  `device_configuration_policies_golden`, `autopilot_policies_golden`,
  `defender_xdr_security_policies_golden` (ADR-0008).

## 3. Still new to the catalog (need migrations when those sources are built)
Devices (`m365_devices`, `itglue_devices`, `website_devices`), apollo company/contact bronze
where not present, and the website/manual bronze tables — per `CLAUDE.md §5` / ADR-0005.
These are not yet implemented in the module; add them with the same conventions when built.

## 4. Silver/gold (front-end owned) follow-on
Bronze lands here; the front-end's silver/gold merge (precedence with `website_*` highest)
should incorporate the new entities (contracts, tickets, proposals, the IT Glue graph, and
security-posture/drift) so the backend agent becomes aware of all of it (`CLAUDE.md §1`).
