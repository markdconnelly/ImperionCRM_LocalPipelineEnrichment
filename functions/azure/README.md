# azure — Azure Resource Manager inventory

Code: [`src/ImperionPipeline/Public/azure/`](../../src/ImperionPipeline/Public/azure)

**Auth:** the certificate-backed Entra app with **`Reader`** across the Azure plane (read-only
by default, CLAUDE.md §2). ARM token resource `https://management.azure.com/.default`.

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionArmRequest` ✓ | GET an ARM collection, follow `nextLink`, return all items. Shared read primitive. |

## get (per object)
| Function | Object | ARM surface |
| --- | --- | --- |
| `Get-ImperionAzureSubscription` ✓ | Subscriptions | `/subscriptions` |
| `Get-ImperionAzureResourceGroup` ✓ | Resource groups | `/subscriptions/{id}/resourcegroups` |
| `Get-ImperionAzureResource` ✓ | Resources | `/subscriptions/{id}/resources` |
| `Get-ImperionAzureSentinel` ☐ | Sentinel rules/workbooks/watchlists | `…/providers/Microsoft.SecurityInsights/*` |

> `posture/Invoke-ImperionAzureInventorySync` remains the end-to-end sweep (it also covers
> management groups + Sentinel); the per-object pairs below are the decomposition the
> `azure/inventory` scheduled task composes. Both upsert on the same keys — idempotent.

## post (per object)
| Function | Target | Shape |
| --- | --- | --- |
| `Set-ImperionAzureSubscriptionToBronze` ✓ | `azure_subscriptions` | standard envelope, projected to the migration-0038 column set (extras stay in `raw_payload`) |
| `Set-ImperionAzureResourceGroupToBronze` ✓ | `azure_resource_groups` | standard envelope, projected |
| `Set-ImperionAzureResourceToBronze` ✓ | `azure_resources` | standard envelope, projected |

## Cadence
Inventory daily. See [`../../scheduled-tasks/`](../../scheduled-tasks).
