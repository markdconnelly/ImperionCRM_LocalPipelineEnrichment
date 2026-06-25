# darkwebid — Dark Web ID (ID Agent) credential-exposure monitoring

Code: [`src/ImperionPipeline/Public/darkwebid/`](../../src/ImperionPipeline/Public/darkwebid)

Dark Web ID (Kaseya / ID Agent) monitors client domains for breached/exposed credentials.
Its findings are **security-posture evidence** about a client `account` and its `contact`s.
Net-new integration to this repo.

**Auth:** **HTTP Basic auth** — a **username + password** pair sent as
`Authorization: Basic <base64(username:password)>` against base **`https://secure.darkwebid.com`**,
with **IP allowlisting** (Kaseya / ID Agent help docs). NOT a bearer API key. Aligned with the
cloud Pipeline's Dark Web ID client (front-end ADR-0040). In the system the credential is a
**company credential** stored as a JSON blob `{username, password}` in Key Vault
`conn-company-darkwebid`; the sync resolves both fields from the `connection` registry via
`Resolve-ImperionCompanyCredential` (ADR-0103) — DB row → KV blob → field — never a raw secret
read. Read-only.

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionDarkWebIdRequest` ✓ | GET a Dark Web ID collection with HTTP Basic auth (username+password), JSON:API paging (`data` + `links.next`), 429/503 backoff, return items. StrictMode-safe. |

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
