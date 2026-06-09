# posture — Microsoft security estate (golden-state drift)

Code: [`src/ImperionPipeline/Public/posture/`](../../src/ImperionPipeline/Public/posture)

The read-only security/identity estate across Graph + ARM (CLAUDE.md §5-posture, ADR-0008).
These are currently **end-to-end sync cmdlets** (get + flatten + IT Glue + Postgres in one);
they predate the connect/get/post split and will be decomposed as the per-object layers fill
in. The folder name `posture` folds in what the user-added `entra` folder covered (service
principals, Conditional Access).

**Auth:** the certificate-backed Entra app — Graph + ARM, read-only.

## Sync cmdlets (scheduled-task entry points)
| Function | What | Tables |
| --- | --- | --- |
| `Invoke-ImperionServicePrincipalSync` ✓ | Entra service principals → IT Glue + Postgres | `m365_service_principals` |
| `Invoke-ImperionSecureScoreSync` ✓ | Secure Score snapshots + control profiles | `secure_scores`, `secure_score_control_profiles` |
| `Invoke-ImperionPolicySync` ✓ | CA / Intune / device-config / Autopilot / Defender XDR policies | `*_policies` (+ `*_golden`) |
| `Invoke-ImperionAzureInventorySync` ✓ | Mgmt groups, subscriptions, RGs, resources, Sentinel | `sql/azure_inventory_schema.sql` |

## Golden state / drift
| Function | Purpose |
| --- | --- |
| `Get-ImperionPolicyDrift` ✓ | Flag **compliant / drift / ungoverned / missing** vs the approved baseline. |
| `Set-ImperionPolicyGoldenState` ✓ | Promote a current policy to baseline (**human-gated**). |

See [`docs/database/golden-states-and-drift.md`](../../docs/database/golden-states-and-drift.md)
and [`docs/integrations/secure-score.md`](../../docs/integrations/secure-score.md).

## Cadence
Secure Score + policies daily; inventory daily; drift on the same cadence as the sync.
See [`../../scheduled-tasks/`](../../scheduled-tasks).
