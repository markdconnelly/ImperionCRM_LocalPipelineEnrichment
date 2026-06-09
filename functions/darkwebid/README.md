# darkwebid — Dark Web ID (ID Agent) credential-exposure monitoring

Code: [`src/ImperionPipeline/Public/darkwebid/`](../../src/ImperionPipeline/Public/darkwebid)

Dark Web ID (Kaseya / ID Agent) monitors client domains for breached/exposed credentials.
Its findings are **security-posture evidence** about a client `account` and its `contact`s.
Net-new integration to this repo.

**Auth:** OAuth2 **client-credentials** against the ID Agent token endpoint — client id +
secret from the SecretStore (`DarkWebIdClientId`, `DarkWebIdClientSecret`) → short-lived bearer.
Read-only.

## connect (planned)
| Function | Purpose |
| --- | --- |
| `Connect-ImperionDarkWebId` ☐ | Client-credentials grant → cached short-lived bearer token. |
| `Invoke-ImperionDarkWebIdRequest` ☐ | GET a Dark Web ID collection with the bearer, page, backoff, return items. |

## get (planned — per object)
| Function | Object |
| --- | --- |
| `Get-ImperionDarkWebIdDomain` ☐ | Monitored domains (→ `account`) |
| `Get-ImperionDarkWebIdCompromise` ☐ | Compromise / exposure records (per credential/contact) |

## post (planned)
`Set-ImperionDarkWebId*ToBronze` ☐. **No destination table exists yet** in the shared schema —
a `dark_web_id_*` bronze (or an `assessment_artifact` mapping) needs a **front-end migration
first** (CLAUDE.md §5/§6). Track as a cross-repo checklist item; this repo fails loudly on a
missing table rather than creating one.

## Provenance & consent
Exposure data is sensitive: every row stamped `source` / `collected_at` / `lawful_basis`.
Having the data is **never** consent to contact (system consent gate).

## Cadence
Daily. See [`../../scheduled-tasks/`](../../scheduled-tasks).
