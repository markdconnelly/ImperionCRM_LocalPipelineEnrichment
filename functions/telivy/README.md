# telivy — Telivy security assessments

Code: [`src/ImperionPipeline/Public/telivy/`](../../src/ImperionPipeline/Public/telivy)

Telivy is a security-assessment / analytics platform. Its outputs are **assessment evidence**:
in the data model they land as `assessment_artifact` rows with `source = televy`
(front-end data-model Diagram 4). Net-new integration to this repo.

> Naming note: the front-end enum spells it **`televy`**; this area folder uses the vendor's
> spelling **telivy**. The `source` value written to Postgres must be `televy` to match the
> `assessment_artifact.source` enum.

**Auth:** `x-api-key` header from the SecretStore secret **`Telivy-API-Key`** (aligned with the
cloud Pipeline's Televy client, ADR-0040). Read-only.

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionTelivyRequest` ✓ | GET a Telivy collection with `x-api-key` auth, JSON:API paging (`data` + `links.next`), 429/503 backoff, return items. StrictMode-safe. |

## get (planned — per object)
| Function | Object |
| --- | --- |
| `Get-ImperionTelivyOrganization` ☐ | Client orgs / scans mapped to an `account` |
| `Get-ImperionTelivyAssessment` ☐ | Assessment results / risk scores → `assessment_artifact` |
| `Get-ImperionTelivyReport` ☐ | Report artifacts (`kind = report`) |

## post (planned)
`Set-ImperionTelivy*ToBronze` ☐ → bronze **`televy_reports`** (front-end migration `0043`,
ADR-0039 per-source shape: `external_ref` / `payload_bronze`), which a merge folds into
`assessment_artifact` (`source = televy`). Tables exist — no new migration needed.

## Cadence
Daily (assessments change slowly). See [`../../scheduled-tasks/`](../../scheduled-tasks).
