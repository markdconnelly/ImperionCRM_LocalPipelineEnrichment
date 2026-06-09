-- azure_inventory_schema.sql
-- PROPOSED migration (front-end-owned schema — ADR-0005). Bronze targets for the Entra
-- service-principal sync and the Azure + Sentinel inventory.
-- BRONZE IS LOSSLESS/RAW: flat columns are **text** (the loader coerces every value to a
-- stable string — dates to ISO 8601); true types live in raw_payload (jsonb) and silver casts.
-- Standard envelope on every table: tenant_id, source, external_id, collected_at, raw_payload,
-- content_hash; PK (tenant_id, source, external_id).

CREATE TABLE IF NOT EXISTS m365_service_principals (
    app_id                     text,
    display_name               text,
    sp_type                    text,
    account_enabled            text,
    app_owner_org_id           text,
    sign_in_audience           text,
    homepage                   text,
    reply_urls                 text,
    sp_names                   text,
    tags                       text,
    app_roles_count            text,
    oauth2_scopes_count        text,
    key_credentials_count      text,
    key_credential_next_expiry text,
    pwd_credentials_count      text,
    pwd_credential_next_expiry text,
    created_date_time          text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS azure_management_groups (
    name text, display_name text, mg_tenant_id text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS azure_subscriptions (
    display_name text, state text, sub_tenant_id text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS azure_resource_groups (
    name text, location text, subscription_id text, provisioning_state text, tags text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS azure_resources (
    name text, type text, location text, resource_group text, subscription_id text,
    sku text, kind text, tags text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS sentinel_analytic_rules (
    name text, display_name text, rule_kind text, enabled text, severity text,
    tactics text, last_modified text, workspace text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS sentinel_automation_rules (
    display_name text, rule_order text, workspace text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS sentinel_watchlists (
    display_name text, provider text, ws_source text, updated text, workspace text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS sentinel_workbooks (
    display_name text, category text, version text, time_modified text, subscription_id text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);
