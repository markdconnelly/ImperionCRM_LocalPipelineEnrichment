# kaseya — Kaseya-stack bulk bronze loader

Code: [`src/ImperionPipeline/Public/kaseya/`](../../src/ImperionPipeline/Public/kaseya)

Pure CRM/support data from the Kaseya stack (Autotask + Kaseya Quote Manager) that flattens
**straight to Postgres bronze**, skipping the IT Glue hub (ADR-0006).

| Function | What | Tables |
| --- | --- | --- |
| `Invoke-ImperionKaseyaImport` ✓ | Bulk-load Autotask contracts + tickets and KQM proposals into bronze with change-detecting upserts; resolves the Autotask zone then pages `/{Entity}/query`. | `autotask_contract_bronze`, `autotask_ticket_bronze`, `kqm_proposal_bronze` |

> This is the **legacy monolith** for the Kaseya sources. Its Autotask half is the reference
> for the reusable [`autotask/`](../autotask) `connect` layer; as that layer + per-object `get`
> functions land, this importer is superseded by the per-(source,entity) tasks.

See [`docs/integrations/kaseya-quotes-proposals.md`](../../docs/integrations/kaseya-quotes-proposals.md).

## Cadence
Daily bulk reconcile. See [`../../scheduled-tasks/`](../../scheduled-tasks).
