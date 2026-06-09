-- security_posture_schema.sql
-- PROPOSED migration (front-end-owned schema — ADR-0005). Adds Microsoft Secure Score, the
-- observed (current-state) security-posture policy tables, and the GOLDEN-STATE tables that
-- hold the approved baseline for drift detection (ADR-0008).
-- BRONZE IS LOSSLESS/RAW: flat columns are **text** (the loader coerces every value to a
-- stable string — dates to ISO 8601); true types live in raw_payload (jsonb) and silver casts.
-- Envelope on observed/bronze tables: tenant_id, source, external_id, collected_at, raw_payload,
-- content_hash; PK (tenant_id, source, external_id).

-- ── Microsoft Secure Score ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS secure_scores (
    current_score       text,
    max_score           text,
    active_user_count   text,
    licensed_user_count text,
    enabled_services    text,
    created_date_time   text,
    azure_tenant_id     text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS secure_score_control_profiles (
    control_name        text,
    control_category    text,
    title               text,
    max_score           text,
    rank                text,
    service             text,
    action_type         text,
    user_impact         text,
    implementation_cost text,
    tier                text,
    threats             text,
    remediation         text,
    deprecated          text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- ── Observed security-posture policies (current state) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS entra_conditional_access_policies (
    policy_name text, state text, created_date_time text, modified_date_time text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS intune_security_policies (
    policy_name text, template_family text, technologies text, platforms text, modified_date_time text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS device_configuration_policies (
    policy_name text, odata_type text, created_date_time text, modified_date_time text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS autopilot_policies (
    policy_name text, locale text, created_date_time text, modified_date_time text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

CREATE TABLE IF NOT EXISTS defender_xdr_security_policies (
    policy_name text, template_family text, technologies text, platforms text, modified_date_time text,
    tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
    collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
    PRIMARY KEY (tenant_id, source, external_id)
);

-- ── Golden states (approved baseline; keyed on tenant_id + policy_id) ────────────────────
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'conditional_access_policies_golden',
        'intune_security_policies_golden',
        'device_configuration_policies_golden',
        'autopilot_policies_golden',
        'defender_xdr_security_policies_golden'
    ] LOOP
        EXECUTE format($f$
            CREATE TABLE IF NOT EXISTS %s (
                tenant_id      text  NOT NULL,
                policy_id      text  NOT NULL,
                policy_name    text,
                golden_hash    text  NOT NULL,
                golden_payload jsonb NOT NULL,
                approved_by    text,
                approved_at    text,
                notes          text,
                PRIMARY KEY (tenant_id, policy_id)
            )$f$, t);
    END LOOP;
END $$;
