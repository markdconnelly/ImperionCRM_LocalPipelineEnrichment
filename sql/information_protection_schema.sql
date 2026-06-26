-- information_protection_schema.sql
-- REFERENCE (front-end-owned schema — ADR-0005). The information-protection / classification
-- bronze tables were APPLIED to prod by front-end ImperionCRM#575 (NOT under the names this file
-- originally proposed for #259). This file now mirrors the APPLIED shape so the LP collectors
-- (drift-corrected in local issue #372) stay reconciled to it. Schema is owned by the front end;
-- this repo never runs these — they are kept here as the contract the collectors write against.
--
-- Targets: Microsoft Purview sensitivity labels and Entra custom security attribute DEFINITIONS.
-- BRONZE IS LOSSLESS/RAW: flat columns are **text**; true types live in raw_payload (jsonb) and
-- silver casts. Standard envelope on every table: tenant_id, source, external_id, collected_at,
-- raw_payload, content_hash; PK (tenant_id, source, external_id). Logical source = 'm365'.
--
-- The benchmark-vs-golden classification (compliant / drift / ungoverned / missing) runs in the
-- front-end posture merge per the golden-baseline pattern (#575); bronze just lands the taxonomy.

CREATE TABLE IF NOT EXISTS m365_sensitivity_labels (
    label_id   text,            -- Graph label id (= external_id), surfaced as a flat column
    name       text,
    priority   text,            -- ordering priority of the label (Graph `sensitivity`)
    is_active  text,
    -- description, tooltip, applies-to, rights, the full sublabel tree: lossless in raw_payload
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS entra_custom_security_attributes (
    attribute_set text,
    name          text,
    data_type     text,         -- String / Integer / Boolean (Graph `type`)
    status        text,         -- Available / Deprecated
    -- description, collection/searchable/predefined-only flags, allowed values: in raw_payload
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- DEFINITIONS only. Per-principal custom-security-attribute ASSIGNMENTS (the key=value tags on
-- individual users/SPs) are a heavier, principal-joined, PII-bearing surface deferred to a
-- follow-up (CustomSecAttributeAssignment.Read.All) — see docs/integrations/information-protection.md.

-- GRANT prerequisite (front-end 0044 pattern): the imperion-localpipeline role holds SELECT,
-- INSERT, UPDATE (no DELETE) on both tables so the cert-backed SP can write them (ADR-0003 —
-- role scoped to exactly the tables this repo touches).
