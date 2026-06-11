# ADR-0005: Source bronze catalog + table-naming reconciliation

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Proposed (needs front-end migration sign-off) |
| **Date** | 2026-06-08 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | ADR-0006; front-end ADR-0017; front-end ADR-0039; pipeline ADR-0009 |

## Problem

This repo ingests a broad source catalog (companies, contacts, devices, proposals,
contracts, tickets). The existing per-source bronze tables follow `{source}_companies` /
`{source}_contacts` / `{source}_devices` (pipeline ADR-0009 / front-end ADR-0039). Mark's
catalog uses a `_bronze` suffix. The **front-end repo owns the schema and all migrations**
— this repo never creates tables.

**Bronze catalog (source names)**

| Entity | Sources |
| --- | --- |
| Companies | `autotask` · `itglue` · `apollo` · `website` |
| Contacts | `m365` · `itglue` · `autotask` · `apollo` · `website` |
| Devices | `m365` · `itglue` · `website` |
| Proposals | `kqm` · `website` |
| Contracts | `autotask` · `docusign` |
| Tickets | `autotask` |

## Options considered

None recorded in the original ADR.

## Decision

1. **Adopt the existing `{source}_{entity}` physical-table convention** (not a `_bronze`
   suffix) for consistency with the sibling pipeline; the `_bronze` name is the *logical*
   source key. *(Open: confirm with the front-end repo owner.)*
2. **New tables required** — these have no schema yet and need front-end migrations before
   the loaders can write: proposals (`kqm`, `website`), contracts (`autotask`, `docusign`),
   tickets (`autotask`), and the device set (`m365`, `itglue`, `website`) where not already
   present. Plus the **IT Glue export tables + relationship edge table** (ADR-0006).
3. **`website_*` is highest merge precedence** (manual web-app entries), consistent with
   front-end ADR-0039 / pipeline ADR-0009.
4. **Loaders fail loudly** on a missing table rather than creating it. A
   `sql/` directory holds the **proposed DDL** as a migration request for the front-end repo;
   an optional `-EnsureSchema` dev switch may apply it locally but is **off by default**.

## Consequences

- **Security/cost:** none material.
- **Operational impact:** a cross-repo checklist gates first ingestion of each new entity.

## Future considerations

- **Future considerations:** keep the source-key→table map in one module file mirroring the
  pipeline's `shared/medallion.ts`.

## Cross-references

This repo `CLAUDE.md §5–§6`; front-end ADR-0017 (schema ownership), front-end ADR-0039 + pipeline
ADR-0009 (per-source bronze + website precedence).
