# Integration — Autotask Opportunities field probe (#1325)

**Purpose.** Confirm the live Autotask **Opportunities** entity field shape against the
planned `autotask_opportunities` bronze (front-end migration 0083) and the renewals epic
(ImperionCRM#1304) before the collector is built — the #1325 / #430 follow-up. The
front-end design doc is `ImperionCRM/docs/integrations/autotask-opportunities-api.md`; this
is the LP-side probe that verifies it against the live API.

## The cmdlet
`Get-ImperionAutotaskOpportunityField` (read-only, get-layer; the KQM
`Get-ImperionKqmFieldName` precedent). It calls the Autotask REST
`Opportunities/entityInformation/fields` endpoint and returns a flat table of field
**metadata only**:

| Column | Meaning |
| --- | --- |
| `name` | Autotask field name (maps to the bronze column / `raw_payload` key) |
| `dataType` | field type (string/integer/decimal/dateTime/boolean) |
| `isRequired` / `isQueryable` / `isReadOnly` | constraint flags |
| `isPickList` | whether the field is a picklist |
| `length` | max length (strings) |
| `picklist` | **active** picklist entries as `value=label; …` (e.g. stage / status decode) |

Auth is the shared Autotask 3-part header via `Get-ImperionAutotaskContext` (zone discovery
+ `ApiIntegrationCode`/`UserName`/`Secret` from the SecretStore). Requires
`Initialize-ImperionContext`.

## Run it
```powershell
Import-Module ImperionPipeline; Initialize-ImperionContext
Get-ImperionAutotaskOpportunityField | Format-Table -Auto
# picklist decodes only:
Get-ImperionAutotaskOpportunityField | Where-Object isPickList | Select-Object name, picklist
```

## Safety — field metadata only, NEVER records
The probe **does not query any Opportunity records**. Field names, types, and picklist
labels are schema metadata and are safe to paste into issue #1325. Row-level Opportunity
data is **client PII** and must never enter an issue/PR/commit (system CLAUDE.md §8) — to
confirm a field's live *values*, query the live read-only DB after the collector ingests
bronze, not from this probe. Inactive picklist entries are dropped (they don't constrain
new bronze).

## Next
Feed the confirmed shape back into #1325 (close the probe), then build
`Get-ImperionAutotaskOpportunity` → `autotask_opportunities` bronze (0083) + the silver
opportunity merge for the renewals epic.
