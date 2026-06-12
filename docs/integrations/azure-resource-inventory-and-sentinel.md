# Integration — Azure resource inventory + Microsoft Sentinel → IT Glue

**Purpose.** Inventory and document the Azure estate — **management groups, subscriptions,
resource groups, resources** — and, where a Sentinel workspace exists, its **analytic
rules, automation rules, workbooks, and watchlists**. Flatten each to a flat table,
document in IT Glue (related to the owning subscription/resource group), and land in
Postgres bronze. **Check for updates; if nothing changed, move on.**

## Auth
- **Cert-based app-only** token for Azure Resource Manager, scope
  `https://management.azure.com/.default`, in the **partner tenant**.
- **Roles required (read-only, ADR-0002):** `Reader` at the management-group/subscription
  scope covers ARM resources and Sentinel rule reads. (`Microsoft Sentinel Reader` if a
  given tenant scopes Sentinel separately.)

## Source endpoints (ARM REST)
| Object | Endpoint (api-version may need bumping) |
| --- | --- |
| Management groups | `GET /providers/Microsoft.Management/managementGroups?api-version=2021-04-01` |
| Subscriptions | `GET /subscriptions?api-version=2022-12-01` |
| Resource groups | `GET /subscriptions/{sub}/resourcegroups?api-version=2022-09-01` |
| Resources | `GET /subscriptions/{sub}/resources?api-version=2022-09-01` (or Azure Resource Graph for scale) |
| Log Analytics workspaces | `GET /subscriptions/{sub}/providers/Microsoft.OperationalInsights/workspaces?api-version=2022-10-01` |
| Sentinel analytic rules | `.../workspaces/{ws}/providers/Microsoft.SecurityInsights/alertRules?api-version=2023-11-01` |
| Sentinel automation rules | `.../providers/Microsoft.SecurityInsights/automationRules?api-version=2023-11-01` |
| Sentinel watchlists | `.../providers/Microsoft.SecurityInsights/watchlists?api-version=2023-11-01` |
| Sentinel workbooks | `GET /subscriptions/{sub}/providers/Microsoft.Insights/workbooks?category=sentinel&api-version=2022-04-01` |

**"If they exist":** Sentinel rides on a Log Analytics workspace with the SecurityInsights
solution. Enumerate workspaces first; query Sentinel objects only for workspaces that have
it. A workspace without Sentinel simply yields zero rules — log and move on, not an error.

## Cmdlets (as built)

Two producers exist for the same bronze tables (idempotent — both change-detect on
`content_hash`, so overlap never duplicates):

- **`Invoke-ImperionAzureInventorySync`** — the original monolithic sync (Azure estate +
  Sentinel + management groups in one pass).
- **Per-entity composition (issue #97):** `Get-ImperionSentinelObject` (one traversal:
  subscriptions → workspaces → analytic/automation rules + watchlists, plus per-subscription
  workbooks; rows carry an `entity` discriminator) piped to **`Set-ImperionSentinelToBronze`**
  (multi-table router projecting each entity to its exact migration-0038 column set) — the
  `scheduled-tasks/azure/sentinel.task.ps1` task. Permissions: the existing **Reader** grant
  only (`*/read`); no new consent.

## Flattened fields (representative)
- **Management group:** `id` · `name` · `displayName` · `tenantId` · `parent`.
- **Subscription:** `subscriptionId` · `displayName` · `state` · `tenantId` · mgmt-group parent.
- **Resource group:** `id` · `name` · `location` · `subscriptionId` · `tags` (joined) · `provisioningState`.
- **Resource:** `id` · `name` · `type` · `location` · `resourceGroup` · `subscriptionId` · `sku` · `kind` · `tags` (joined).
- **Analytic rule:** `id` · `name` · `displayName` · `kind` · `enabled` · `severity` · `tactics` (joined) · `query` (hash only, or stored to gold) · `lastModifiedUtc`.
- **Automation rule:** `id` · `displayName` · `order` · `triggeringLogic` summary · `enabled`.
- **Watchlist:** `id` · `displayName` · `provider` · `itemsCount` · `source` · `updated`.
- **Workbook:** `id` · `displayName` · `category` · `version` · `timeModified`.

## Change detection
Per object, hash the flattened record (+ for rules, the rule definition). Compare to the
last `content_hash` in bronze. Unchanged → skip IT Glue write + Postgres upsert and log
`unchanged`. This is the "check for updates, if nothing changed move on" requirement.

## IT Glue modeling
Flexible Asset Types: `Azure Management Group`, `Azure Subscription`, `Azure Resource
Group`, `Azure Resource`, `Sentinel Analytic Rule`, `Sentinel Automation Rule`, `Sentinel
Workbook`, `Sentinel Watchlist`. Tag-trait relationships: resource → resource group →
subscription → management group; Sentinel objects → their subscription/workspace org.

## Postgres target (bronze)
`azure_management_groups`, `azure_subscriptions`, `azure_resource_groups`,
`azure_resources`, `sentinel_analytic_rules`, `sentinel_automation_rules`,
`sentinel_workbooks`, `sentinel_watchlists` — each with `tenant_id`, `source` (`azure`/
`sentinel`), `external_id`, `content_hash`, `collected_at`, `raw_payload`.

## Rate limits & retry
ARM throttles per-subscription; honor `Retry-After`/429 backoff. For large estates prefer
**Azure Resource Graph** (`/providers/Microsoft.ResourceGraph/resources`) to page resources
efficiently.

## Assumptions to confirm on first live run
- Exact api-versions available in the tenant (bump as needed).
- Whether resource enumeration uses ARM list or Resource Graph (Resource Graph recommended
  at scale).
