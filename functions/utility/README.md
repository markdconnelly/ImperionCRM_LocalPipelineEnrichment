# utility — cross-cutting building blocks

Code: [`src/ImperionPipeline/Public/utility/`](../../src/ImperionPipeline/Public/utility)

Not tied to any one API. Everything in the `connect`/`get`/`post` layers reuses these.

## Runtime / setup
| Function | Purpose |
| --- | --- |
| `Initialize-ImperionContext` ✓ | Load `%ProgramData%\Imperion\` config, unlock the SecretStore, prime token/DB plumbing. Call once per session. |
| `Initialize-ImperionUnattended` ✓ | One-time bootstrap proof: CMS-unlock + cert token + DB round-trip with no human present (CLAUDE.md §10.2). |
| `Connect-ImperionSecretStore` ✓ | CMS-decrypt the vault password with the machine cert and `Unlock-SecretStore`. |
| `Get-ImperionAccessToken` ✓ | Cert-app token for a resource+tenant (Graph / ARM / Postgres). Cached per `(tenant, resource)`. GDAP for client tenants. |
| `Register-ImperionTask` ✓ | Register a scheduled task that runs one cmdlet under the gMSA/service identity. |

## Data plumbing
| Function | Purpose |
| --- | --- |
| `Open-ImperionDbConnection` ✓ | Open an Npgsql connection over TLS with a short-lived Entra token (no stored DB password, ADR-0003). |
| `Invoke-ImperionDbQuery` ✓ | Parameterized read → `[PSCustomObject]` rows. |
| `Invoke-ImperionDbNonQuery` ✓ | Parameterized write/DDL-free command. |
| `Invoke-ImperionBronzeUpsert` ✓ | Idempotent upsert of a flat table on `(tenant, source, external_id)` with content-hash change detection → `{scanned, inserted, updated, unchanged}`. |

## Shaping & observability
| Function | Purpose |
| --- | --- |
| `ConvertTo-ImperionFlatObject` ✓ | Flatten a source record to the standard flat-table envelope (`tenant_id, source, external_id, content_hash, collected_at, raw_payload` + mapped columns). The repo's universal currency. |
| `Get-ImperionContentHash` ✓ | Order-stable hash of the meaningful columns (excludes volatile fields) — drives dedup / no-re-embed. |
| `Join-ImperionValues` ✓ | Collapse an array to a stable `'; '`-joined scalar for a flat column. |
| `Write-ImperionLog` ✓ | Structured JSON log line (run id, source, tenant, counts, duration, cost). No `Write-Host` for data. |

Private helpers backing these (module-internal): `Get-ImperionConfig`, `Get-ImperionSecretNames`,
`Get-ImperionSecretValue`, `Get-ImperionGraphToken`, `Get-ImperionArmToken`,
`New-ImperionDbConnection`, `Initialize-ImperionNpgsql`, `Invoke-ImperionRestWithRetry`,
`Get-ImperionPropertyPath`.
