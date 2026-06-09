-- kaseya_bronze_schema.sql
-- PROPOSED migration (front-end-owned schema — ADR-0005). Bronze targets for the Kaseya
-- stack: Autotask (contracts, tickets — and companies/contacts) + KQM proposals + the
-- DocuSign/website counterparts. Autotask columns are the curated subset confirmed against
-- the LIVE Autotask field-metadata API (entityInformation/fields); the full payload is kept
-- in raw_payload. BRONZE IS LOSSLESS/RAW: flat columns are text, silver casts.
-- Envelope + PK (tenant_id, source, external_id).
--
-- NOTE: autotask_companies / autotask_contacts likely ALREADY EXIST in the front-end schema
-- (the cloud Pipeline polls them — front-end ADR-0039 / pipeline ADR-0009). Reconcile column
-- names before adding; this local module does NOT write companies/contacts today (the cloud
-- Pipeline owns those) — they are included here only for completeness of the catalog.

-- ── Autotask: Contracts (confirmed fields) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS autotask_contracts (
    contract_name text, contract_number text, company_id text, contact_id text, contact_name text,
    contract_type text, contract_category text, status text, billing_preference text, description text,
    start_date text, end_date text, estimated_cost text, estimated_revenue text, estimated_hours text,
    setup_fee text, is_compliant text, is_default_contract text, opportunity_id text,
    purchase_order_number text, service_level_agreement_id text, last_modified_date_time text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- ── Autotask: Tickets (confirmed fields) ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS autotask_tickets (
    ticket_number text, title text, status text, priority text, company_id text, contact_id text,
    contract_id text, queue_id text, issue_type text, sub_issue_type text, ticket_type text,
    ticket_category text, assigned_resource_id text, creator_resource_id text, create_date text,
    due_date_time text, completed_date text, resolved_date_time text, first_response_date_time text,
    last_activity_date text, last_tracked_modification_date_time text, description text,
    resolution text, ticket_source text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- ── Autotask: Companies / Contacts (likely already exist — reconcile before applying) ────
CREATE TABLE IF NOT EXISTS autotask_companies (
    company_name text, company_number text, company_type text, classification text,
    parent_company_id text, owner_resource_id text, phone text, fax text, web_address text,
    address1 text, address2 text, city text, state text, postal_code text, country_id text,
    is_active text, is_tax_exempt text, last_activity_date text, last_tracked_modified_date_time text,
    create_date text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS autotask_contacts (
    company_id text, first_name text, last_name text, title text, email_address text,
    phone text, mobile_phone text, is_active text, primary_contact text, city text, state text,
    zip_code text, last_activity_date text, last_modified_date text, create_date text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- ── KQM proposals / website proposals / DocuSign contracts (no API access yet — assumptions) ─
CREATE TABLE IF NOT EXISTS kqm_proposals (
    name text, status text, total text, account_ref text, created_at text, updated_at text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS website_proposals (
    name text, status text, total text, account_ref text, created_at text, updated_at text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS docusign_contracts (
    subject text, status text, account_ref text, sent_at text, completed_at text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);
