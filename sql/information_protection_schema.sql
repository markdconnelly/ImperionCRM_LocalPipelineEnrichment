-- information_protection_schema.sql
-- PROPOSED migration (front-end-owned schema — ADR-0005; front-end request ImperionCRM#259,
-- local issue #141). Bronze targets for the information-protection / classification collectors:
-- Microsoft Purview sensitivity labels and custom security attribute DEFINITIONS.
-- BRONZE IS LOSSLESS/RAW: flat columns are **text** (the loader coerces every value to a stable
-- string — dates to ISO 8601); true types live in raw_payload (jsonb) and silver casts.
-- Standard envelope on every table: tenant_id, source, external_id, collected_at, raw_payload,
-- content_hash; PK (tenant_id, source, external_id). Logical source = 'm365'.
--
-- The benchmark-vs-golden classification (compliant / drift / ungoverned / missing) runs in the
-- front-end posture merge per the golden-baseline pattern (#259); bronze just lands the taxonomy.

CREATE TABLE IF NOT EXISTS sensitivity_labels (
    label_name        text,
    display_name      text,
    description       text,
    is_active         text,
    is_appendable     text,
    sensitivity       text,   -- ordering priority of the label
    tooltip           text,
    applies_to        text,
    parent_label_id   text,   -- labels nest (sublabels); the full tree lives in raw_payload
    parent_label_name text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS custom_security_attribute_definitions (
    attribute_set              text,
    attribute_name             text,
    description                text,
    type                       text,   -- String / Integer / Boolean
    status                     text,   -- Available / Deprecated
    is_collection              text,
    is_searchable              text,
    use_predefined_values_only text,   -- free-form vs. predefined list
    allowed_values             text,   -- joined active predefined values; full list in raw_payload
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- DEFINITIONS only. Per-principal custom-security-attribute ASSIGNMENTS (the key=value tags on
-- individual users/SPs) are a heavier, principal-joined, PII-bearing surface deferred to a
-- follow-up (CustomSecAttributeAssignment.Read.All) — see docs/integrations/information-protection.md.

-- GRANT prerequisite (front-end 0044 pattern): add these two tables to the
-- imperion-localpipeline role's SELECT, INSERT, UPDATE grant list (no DELETE) so the
-- cert-backed SP can write them (ADR-0003 — role scoped to exactly the tables this repo touches).
