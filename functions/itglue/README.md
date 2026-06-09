# itglue — IT Glue (documentation + relationship hub)

Code: [`src/ImperionPipeline/Public/itglue/`](../../src/ImperionPipeline/Public/itglue)

IT Glue is **both a source and a write target** (CLAUDE.md §6, ADR-0006): operational data is
read from it into bronze, and flattened operational tables are written back into it as
documented, related objects. Writes stay **scoped and gated** — a net-new write surface goes
through human approval.

**Auth:** `Authorization: <read API key>` for reads; a separate **write key** for documentation
writes. Region-aware base URI (`config.ITGlue.BaseUri`).

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionITGlueRequest` ✓ | Page a JSON:API collection (`?page[number]`/`links.next`), return all `data`. Read primitive. |

## get
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionITGlueExport` ✓ | Export the whole IT Glue dataset → Postgres `itglue_<type>` with relationships in `itglue_export_relationship` (delete-then-insert; secrets/passwords never exported). |
| `Get-ImperionITGlueOrganization` / `Configuration` / `Contact` ☐ | Per-object collectors (decomposition of the export above) for the `*_devices` / `*_companies` / `*_contacts` bronze. |

## post
| Function | Purpose |
| --- | --- |
| `Set-ImperionITGlueFlexibleAsset` ✓ | Upsert a flexible asset by match-trait (create the type if missing); the back-write half of flatten→IT Glue→Postgres. |
| `Set-ImperionITGlueRelationship` ☐ | Relate documented objects (config ↔ contact ↔ org ↔ device). |

## Data-model targets
`itglue_*` export tables · bronze `itglue_companies` / `itglue_contacts` / `itglue_devices`
(Diagram 6b) · `external_identity` (provider `itglue`).

## Cadence
Full export daily; targeted per-object refresh as needed. See [`../../scheduled-tasks/`](../../scheduled-tasks).
