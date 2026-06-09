-- itglue_bronze_schema.sql
-- PROPOSED migration (schema is owned by the front-end repo — ADR-0005 / front-end ADR-0017).
-- This is the migration request for the IT Glue export (ADR-0006). Loaders fail loudly if
-- these are absent; they do NOT create them by default.
--
-- Each IT Glue resource type lands in a generic bronze envelope; relationships land in ONE
-- polymorphic edge table (the "many-to-many for open relationship types").

-- Per-type tables (identical generic envelope), created via a loop for brevity. Verified
-- against the live US IT Glue API: organizations/configurations/contacts/locations/domains
-- carry organization-id, name, resource-url, created-at, updated-at; lookup types
-- (manufacturers, models, operating_systems, *_types, *_statuses) carry name + timestamps
-- only (nullable columns absorb this). The full attribute set is kept in raw_payload.
-- NOTE: `documents` and `configuration_interfaces` are NOT top-level collection endpoints
-- (they 404) — they are nested under organizations/configurations and are not exported here.
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'organizations','configurations','contacts','locations',
        'flexible_asset_types','flexible_assets','domains',
        'manufacturers','models','operating_systems',
        'configuration_types','organization_types','organization_statuses'
    ] LOOP
        EXECUTE format($f$
            CREATE TABLE IF NOT EXISTS itglue_%s (
                source          text        NOT NULL DEFAULT 'itglue',
                external_id     text        NOT NULL,
                organization_id text,
                name            text,
                resource_url    text,
                created_at      text,
                updated_at      text,
                collected_at    text        NOT NULL,
                raw_payload     jsonb       NOT NULL,
                content_hash    text        NOT NULL,
                PRIMARY KEY (source, external_id)
            )$f$, t);
    END LOOP;
END $$;

-- Polymorphic relationship edge table (ADR-0006).
CREATE TABLE IF NOT EXISTS itglue_relationship (
    from_type          text        NOT NULL,
    from_id            text        NOT NULL,
    to_type            text        NOT NULL,
    to_id              text        NOT NULL,
    relationship_name  text        NOT NULL,
    collected_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (from_type, from_id, relationship_name, to_type, to_id)
);
CREATE INDEX IF NOT EXISTS ix_itglue_rel_to   ON itglue_relationship (to_type, to_id);
CREATE INDEX IF NOT EXISTS ix_itglue_rel_from ON itglue_relationship (from_type, from_id);
