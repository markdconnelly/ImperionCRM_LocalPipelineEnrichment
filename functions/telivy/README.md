# telivy — Telivy security assessments

Code: [`src/ImperionPipeline/Public/telivy/`](../../src/ImperionPipeline/Public/telivy)

Telivy is a security-assessment / analytics platform. Its outputs are **assessment evidence**:
in the data model they land as `assessment_artifact` rows with `source = televy`
(front-end data-model Diagram 4). Net-new integration to this repo.

> Naming note: the front-end enum spells it **`televy`**; this area folder uses the vendor's
> spelling **telivy**. The `source` value written to Postgres must be `televy` to match the
> `assessment_artifact.source` enum.

**Auth:** Bearer token (API key) from the SecretStore (`TelivyApiKey`). Read-only.

## connect (planned)
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionTelivyRequest` ☐ | GET a Telivy collection with bearer auth, page, 429/503 backoff, return items. |

## get (planned — per object)
| Function | Object |
| --- | --- |
| `Get-ImperionTelivyOrganization` ☐ | Client orgs / scans mapped to an `account` |
| `Get-ImperionTelivyAssessment` ☐ | Assessment results / risk scores → `assessment_artifact` |
| `Get-ImperionTelivyReport` ☐ | Report artifacts (`kind = report`) |

## post (planned)
`Set-ImperionTelivy*ToBronze` ☐ → `assessment_artifact` (`source = televy`). New table mapping
may need a front-end migration — confirm before coding (CLAUDE.md §5).

## Cadence
Daily (assessments change slowly). See [`../../scheduled-tasks/`](../../scheduled-tasks).
