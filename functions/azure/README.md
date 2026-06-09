# azure — Azure Resource Manager inventory

Code: [`src/ImperionPipeline/Public/azure/`](../../src/ImperionPipeline/Public/azure)

**Auth:** the certificate-backed Entra app with **`Reader`** across the Azure plane (read-only
by default, CLAUDE.md §2). ARM token resource `https://management.azure.com/.default`.

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionArmRequest` ✓ | GET an ARM collection, follow `nextLink`, return all items. Shared read primitive. |

## get (planned — per object)
| Function | Object | ARM surface |
| --- | --- | --- |
| `Get-ImperionAzureSubscription` ☐ | Subscriptions | `/subscriptions` |
| `Get-ImperionAzureResourceGroup` ☐ | Resource groups | `/subscriptions/{id}/resourcegroups` |
| `Get-ImperionAzureResource` ☐ | Resources | `/subscriptions/{id}/resources` |
| `Get-ImperionAzureSentinel` ☐ | Sentinel rules/workbooks/watchlists | `…/providers/Microsoft.SecurityInsights/*` |

> The end-to-end inventory sync currently lives in `posture/Invoke-ImperionAzureInventorySync`;
> it will be decomposed into the per-object `get` functions above + thin `post` writers.

## post (planned)
`Set-ImperionAzure*ToBronze` ☐ → Postgres inventory tables (see `sql/azure_inventory_schema.sql`).

## Cadence
Inventory daily. See [`../../scheduled-tasks/`](../../scheduled-tasks).
