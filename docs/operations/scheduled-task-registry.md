# Scheduled-task registry

The pipeline is **many small scheduled tasks** (one per sync cmdlet), not a monolith
(CLAUDE.md §1). Each runs under the dedicated gMSA/service account, "run whether logged on
or not." Register/update them with the **`Register-ImperionTask`** cmdlet (idempotent). Each
task command is `pwsh -Command "Import-Module ImperionPipeline; Initialize-ImperionContext;
<cmdlet>"`.

| Task | Cmdlet | Suggested cadence | Notes |
| --- | --- | --- | --- |
| Entra service principals → IT Glue | `Invoke-ImperionServicePrincipalSync` | daily | partner tenant; GDAP loop optional |
| Azure + Sentinel inventory | `Invoke-ImperionAzureInventorySync` | daily | skips workspaces without Sentinel |
| Secure Score | `Invoke-ImperionSecureScoreSync` | daily | overall + control profiles |
| Security-posture policies + drift | `Invoke-ImperionPolicySync` | daily | CA/Intune/device-config/Autopilot/Defender; drift vs golden |
| IT Glue full export → Postgres | `Invoke-ImperionITGlueExport` | daily/12h | per-type + relationships |
| Kaseya proposals/contracts/tickets | `Invoke-ImperionKaseyaImport` | hourly–daily | bulk upsert, watermarked |
| GDAP relationship health | (build-order task) | hourly | fail-closed surfacing |
| **Gold knowledge + vectorization** | `Invoke-ImperionKnowledgeSync -Vectorize` | nightly 04:30 (after ingests) | composes knowledge_object from silver, chunks (v1), embeds via Voyage @ 1024; chunk-hash idempotent — no re-bill (ADR-0009) |

## Conventions
- Each task invokes **one** module cmdlet after `Initialize-ImperionContext`. No business
  logic in the task definition.
- Tasks are **idempotent**; overlapping runs are prevented (`-MultipleInstances
  IgnoreNew`).
- Every run emits structured JSON logs to `logs/` (run id, source, counts, duration, cost).
- Cadence per source is documented in each `integrations/` doc; tune without code changes.
