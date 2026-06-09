# IT Glue → Postgres: relationship model

How the **entire IT Glue dataset** lands in Postgres **with relationships intact**
(ADR-0006). IT Glue's relationships are open/typed (JSON:API `relationships`), so a fixed
column-per-relation schema doesn't fit. We use **per-type attribute tables + one polymorphic
many-to-many edge table**.

> **Schema ownership.** The front-end repo owns migrations (ADR-0017 / this repo ADR-0005).
> The DDL below is the **proposed migration** (also in [`/sql`](../../sql/)); loaders
> **fail loudly** if the tables are missing and do **not** create them by default.

## Per-type tables
One bronze table per IT Glue resource type, flattened attributes + provenance:

```sql
-- example: organizations (repeat the envelope columns for each type)
CREATE TABLE IF NOT EXISTS itglue_organizations (
    external_id     text        NOT NULL,         -- IT Glue record id
    source          text        NOT NULL DEFAULT 'itglue',
    name            text,
    organization_type text,
    organization_status text,
    -- … the attributes we care about, flattened …
    content_hash    text        NOT NULL,
    collected_at    timestamptz NOT NULL DEFAULT now(),
    raw_payload     jsonb       NOT NULL,
    PRIMARY KEY (source, external_id)
);
-- itglue_configurations, itglue_contacts, itglue_locations,
-- itglue_flexible_assets, itglue_flexible_asset_types, itglue_documents,
-- itglue_domains, itglue_configuration_interfaces, … (same envelope)
```

## The polymorphic edge table (the "many-to-many at the end")
One table captures every relationship, of any type, between any two IT Glue records:

```sql
CREATE TABLE IF NOT EXISTS itglue_relationship (
    from_type          text        NOT NULL,   -- e.g. 'configurations'
    from_id            text        NOT NULL,   -- IT Glue id on the "from" side
    to_type            text        NOT NULL,   -- e.g. 'organizations'
    to_id              text        NOT NULL,   -- IT Glue id on the "to" side
    relationship_name  text        NOT NULL,   -- JSON:API relationship key (e.g. 'organization')
    collected_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (from_type, from_id, relationship_name, to_type, to_id)
);
CREATE INDEX IF NOT EXISTS ix_itglue_rel_to   ON itglue_relationship (to_type, to_id);
CREATE INDEX IF NOT EXISTS ix_itglue_rel_from ON itglue_relationship (from_type, from_id);
```

**Why one edge table, not a junction per pair?** IT Glue relationship *types* are open and
grow over time. A single polymorphic edge table absorbs any new relation with **no schema
change** — and queries stay simple (`WHERE from_type=… AND from_id=…`). This is the
"append a many-to-many to facilitate the open relationship types" requirement, generalized.
*(If a strict per-type junction is later preferred for a hot path, it can be added as a
view/materialized view over this table.)*

## Load algorithm (loader script)
1. For each resource type: page IT Glue (`sort=-updated-at`), flatten, upsert into
   `itglue_<type>` on `(source, external_id)`; skip unchanged `content_hash`.
2. For each record, read its `relationships`; **delete-then-insert** that record's outbound
   edges in `itglue_relationship` (keeps edges convergent on re-run).
3. Watermark the max `updated-at` per type for the next incremental run.

## Excluded
`passwords` and secret-bearing fields are **not** exported (ADR-0006).
