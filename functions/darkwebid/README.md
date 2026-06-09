# darkwebid — Dark Web ID (ID Agent) credential-exposure monitoring

Code: [`src/ImperionPipeline/Public/darkwebid/`](../../src/ImperionPipeline/Public/darkwebid)

Dark Web ID (Kaseya / ID Agent) monitors client domains for breached/exposed credentials.
Its findings are **security-posture evidence** about a client `account` and its `contact`s.
Net-new integration to this repo.

**Auth:** a single API key sent as `Authorization: Bearer <apiKey>`, aligned with the cloud
Pipeline's Dark Web ID client (ADR-0040). In the system the key is a **company credential**
(`conn-company-darkwebid`); locally it's resolved from the SecretStore by the caller and passed
in. Read-only. (Auth scheme is the system's current assumption — "could be x-api-key / Basic /
OAuth"; confirm on first live pull.)

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionDarkWebIdRequest` ✓ | GET a Dark Web ID collection with bearer auth, JSON:API paging (`data` + `links.next`), 429/503 backoff, return items. StrictMode-safe. |

## get (planned — per object)
| Function | Object |
| --- | --- |
| `Get-ImperionDarkWebIdDomain` ☐ | Monitored domains (→ `account`) |
| `Get-ImperionDarkWebIdCompromise` ☐ | Compromise / exposure records (per credential/contact) |

## post (planned)
`Set-ImperionDarkWebId*ToBronze` ☐ → bronze **`darkwebid_exposures`** (front-end migration
`0043`, ADR-0039 per-source shape: `external_ref` / `payload_bronze`), which a merge folds into
silver **`credential_exposure`** (linked to a `contact` by email and `account` by domain).
Tables exist — no new migration needed. This repo owns the **bulk** load; the cloud Pipeline's
darkwebid poll is limited to live GUI-refresh.

## Provenance & consent
Exposure data is sensitive: every row stamped `source` / `collected_at` / `lawful_basis`.
Having the data is **never** consent to contact (system consent gate).

## Cadence
Daily. See [`../../scheduled-tasks/`](../../scheduled-tasks).
