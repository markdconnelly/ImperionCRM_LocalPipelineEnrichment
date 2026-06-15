# easydmarc — EasyDMARC domain / DMARC posture

Code: [`src/ImperionPipeline/Public/easydmarc/`](../../src/ImperionPipeline/Public/easydmarc)

EasyDMARC is Imperion's 3rd-party DNS/DMARC provider. This source ingests per-domain
email-authentication posture (DMARC / SPF / DKIM / BIMI + setup status) into
security-posture bronze — this repo's posture ownership (CLAUDE.md §1). Net-new
integration (issue #122).

**Auth:** a single COMPANY API key (Imperion's MSP account, not per-client) sent as
`Authorization: Bearer <apiKey>`, resolved SecretStore-first / Key Vault-fallback by
`Resolve-ImperionEasyDmarcApiKey` (mirrors the KQM/Meta pattern). Header auth → URLs are
**not** secret-bearing. Read-only / pull-only.

> **GATED (issue #122):** live ingestion is dormant until both the API key is provisioned
> (Mark-gated) AND the front-end bronze migration for `easydmarc_domains` is applied
> (proposed in **ImperionCRM issue #581** — schema is owned by the front-end repo,
> CLAUDE.md §1). The daily task logs + exits cleanly until then.

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionEasyDmarcRequest` ✓ | GET an EasyDMARC collection with bearer auth, `?page=N` paging (`data` + `meta.last_page`), 429/5xx backoff via the retry core, return items. StrictMode-safe. |

## get
| Function | Object |
| --- | --- |
| `Get-ImperionEasyDmarcDomain` ✓ | Monitored domains + DMARC/SPF/DKIM/BIMI posture (→ `account` / domain). external_id = domain name. |
| `Get-ImperionEasyDmarcAggregateReport` ☐ | DMARC RUA aggregate analytics (deferred — field names need a live key) |

## post
| Function | Target |
| --- | --- |
| `Set-ImperionEasyDmarcDomainToBronze` ✓ | → bronze **`easydmarc_domains`** (proposed front-end migration, issue #581; ADR-0039 per-source shape). |

## Provenance
Posture rows stamped `source` / `collected_at` (CLAUDE.md §8). Domain health is operational
truth — no PII collected.

## Cadence
Daily. See [`../../scheduled-tasks/`](../../scheduled-tasks).
