# autotask — Autotask PSA (REST)

Code: [`src/ImperionPipeline/Public/autotask/`](../../src/ImperionPipeline/Public/autotask)

**Auth:** three headers from the SecretStore — `ApiIntegrationCode`, `UserName`, `Secret`
(an API-only user). Autotask is **zone-partitioned**: you first resolve the account's zone
(`/ATServicesRest/v1.0/zoneInformation?user=<UserName>`) then issue all queries against that
zone's base URL. Read-only API user.

> Reference implementation: `kaseya/get/Invoke-ImperionKaseyaImport` already performs the
> zone resolution + `/{Entity}/query` paging inline (field names confirmed against the live
> field-metadata API). The `connect` functions below factor that out for reuse.

## connect (planned)
| Function | Purpose |
| --- | --- |
| `Get-ImperionAutotaskZone` ☐ | Resolve + cache the account's REST zone base URL from `UserName`. |
| `Invoke-ImperionAutotaskRequest` ☐ | POST `/{Entity}/query` with a search filter, page on `pageDetails.nextPageUrl`, return all items. 429/503 backoff. |

## get (planned — per object)
| Function | Object | Entity | Incremental cursor |
| --- | --- | --- | --- |
| `Get-ImperionAutotaskCompany` ☐ | Companies | `Companies` (`companyID`) | `lastActivityDate` |
| `Get-ImperionAutotaskContact` ☐ | Contacts | `Contacts` | `lastActivityDate` |
| `Get-ImperionAutotaskContract` ☐ | Contracts | `Contracts` | `lastModifiedDateTime` |
| `Get-ImperionAutotaskTicket` ☐ | Tickets | `Tickets` | `lastActivityDate` |

## post (planned — per object)
`Set-ImperionAutotask*ToBronze` ☐ → Postgres `autotask_companies` / `autotask_contacts` /
`autotask_contract_bronze` / `autotask_ticket_bronze` (several **new** tables need a front-end
migration first — CLAUDE.md §5).

## Boundary
Bulk scheduled polling lives **here**. Autotask **ticket webhooks** stay in the cloud Pipeline
(ADR-0001) — never duplicated here.

## Cadence
Companies/contacts daily; contracts daily; tickets every 15–30 min (bulk reconcile; webhooks
handle real-time). See [`../../scheduled-tasks/`](../../scheduled-tasks).
