# ADR-0006 — IT Glue as a documentation + relationship hub in the ingestion path

- **Status:** Accepted
- **Date:** 2026-06-08
- **Deciders:** Mark (human), Claude Code

## Problem & context
Mark's established pattern for "most things from Azure": pull the source, **flatten the
JSON to the attributes that matter**, **automatically document them in IT Glue** (relating
them to other IT Glue objects), and from that same flat shape **import into Postgres**. IT
Glue is therefore not just *a source* — it is a documentation + relationship hub in the
middle of the pipeline. We also need to export the **entire** IT Glue dataset into Postgres
with its relationships intact.

## Decision
1. **Canonical pattern:** `Source JSON → flatten to [PSCustomObject] flat table → (a)
   document in IT Glue + relate to other IT Glue objects, and (b) import the same flat
   table into Postgres bronze.` The flat table is the single shared shape.
2. **Scope of the IT Glue write path:** operational / infrastructure data (Entra service
   principals, Azure resources, Sentinel objects, devices, configurations). Pure CRM/sales
   data (Apollo, KQM, DocuSign) flattens **straight to Postgres** — IT Glue step skipped.
3. **Modeling in IT Glue:** use **Flexible Asset Types** (one per documented kind, e.g.
   "Azure Service Principal", "Azure Resource", "Sentinel Analytic Rule"); relationships use
   Flexible-Asset **Tag** traits pointing at Organizations / Configurations / other
   Flexible Assets.
4. **IT Glue → Postgres export with relationships:** one bronze table per IT Glue resource
   type (flattened attributes) **plus a polymorphic many-to-many edge table**
   `itglue_relationship(from_type, from_id, to_type, to_id, relationship_name)` capturing
   IT Glue's open/JSON:API relationships. See
   [itglue-to-postgres-relationships.md](../database/itglue-to-postgres-relationships.md).
5. **Writes stay scoped and gated** (system posture): IT Glue documentation writes never
   push beyond agreed scope; a net-new write surface is a human-approval gate.

## Consequences
- **Security impact:** IT Glue holds sensitive operational data; the export reads broadly —
  secrets/passwords are **excluded** from the Postgres export by default.
- **Cost impact:** IT Glue API rate limits govern throughput; change-detection avoids
  needless writes.
- **Operational impact:** flexible-asset-type creation is a one-time setup per kind,
  idempotent on re-run.
- **Future considerations:** the single edge table generalizes to any new IT Glue relation
  without schema change.

## Cross-references
This repo `CLAUDE.md §6`; [integrations/itglue.md](../integrations/itglue.md);
`ImperionCRM_Pipeline/CLAUDE.md §5` (IT Glue write-path gating).
