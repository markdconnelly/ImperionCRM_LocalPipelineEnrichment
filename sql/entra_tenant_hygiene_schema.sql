-- entra_tenant_hygiene_schema.sql
-- PROPOSED migration (front-end-owned schema — ADR-0005; front-end request ImperionCRM#260,
-- local issue #142). Bronze targets for the tenant-hygiene collectors: Entra domains,
-- application registrations, and directory role assignments.
-- BRONZE IS LOSSLESS/RAW: flat columns are **text** (the loader coerces every value to a
-- stable string — dates to ISO 8601); true types live in raw_payload (jsonb) and silver casts.
-- Standard envelope on every table: tenant_id, source, external_id, collected_at, raw_payload,
-- content_hash; PK (tenant_id, source, external_id). Logical source = 'm365'.
--
-- These are the directory-config gap left by m365_service_principals (the per-tenant app
-- *instance*, already covered): app *registrations* are the app definition; domains and
-- role assignments are the tenant's verification + privileged-membership posture. The
-- benchmark-vs-standard surface (#260) reads the flat hygiene columns called out below.

CREATE TABLE IF NOT EXISTS entra_domains (
    domain_name                          text,
    authentication_type                  text,
    is_default                           text,
    is_initial                           text,
    is_root                              text,
    is_verified                          text,
    is_admin_managed                     text,
    supported_services                   text,
    password_validity_period_in_days     text,
    password_notification_window_in_days text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS entra_app_registrations (
    app_id                         text,
    display_name                   text,
    sign_in_audience               text,
    publisher_domain               text,
    verified_publisher             text,
    identifier_uris                text,
    tags                           text,
    required_resource_access_count text,
    key_credentials_count          text,   -- hygiene: credential count + nearest expiry
    key_credential_next_expiry     text,
    pwd_credentials_count          text,
    pwd_credential_next_expiry     text,
    created_date_time              text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS entra_role_assignments (
    role_definition_id     text,
    role_display_name      text,   -- hygiene: who holds privileged roles (e.g. Global Administrator)
    role_is_builtin        text,
    role_template_id       text,
    principal_id           text,
    principal_display_name text,
    principal_type         text,   -- user / group / servicePrincipal (trimmed from @odata.type)
    principal_upn          text,
    directory_scope_id     text,
    app_scope_id           text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- GRANT prerequisite (front-end 0044 pattern): add these three tables to the
-- imperion-localpipeline role's SELECT, INSERT, UPDATE grant list (no DELETE) so the
-- cert-backed SP can write them (ADR-0003 — role scoped to exactly the tables this repo touches).
