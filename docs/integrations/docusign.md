# Integration — DocuSign envelopes → bronze `docusign_contracts` (issue #99)

Pulls **DocuSign envelopes** (the signed-contract lifecycle: sent → delivered →
completed / declined / voided) into the bronze table `docusign_contracts`
(front-end migration 0038). The cloud Pipeline's `mergeDocusignContractSources`
(front-end ADR-0044) sweeps that bronze into silver `contract`, resolving
`account_ref` (an email / domain / company name — this collector emits the **first
signer's email**) to the owning account; unmatched refs land unlinked and re-try on a
later sweep.

Pure CRM/sales data → **flattens straight to Postgres**; the IT Glue hub step is skipped
(CLAUDE.md §6, ADR-0006).

## Auth & credentials (GATED until provisioned)

| Secret (SecretStore, CLAUDE.md §2) | Name key (`config/secret-names`) | Holds |
| --- | --- | --- |
| `docusign-token` | `DocuSignToken` | OAuth access token (bearer) |
| `docusign-account-id` | `DocuSignAccountId` | eSignature API account id (GUID from OAuth userinfo) |

**Gating:** `scheduled-tasks/docusign/envelopes.task.ps1` wraps the pull in a catch that
logs (`Warn`, source `docusign`) and exits cleanly when either secret is missing or the
token is rejected — the schedule never crashes; the next run converges after the operator
re-provisions.

**CONFIRM BEFORE LIVE USE (ADR-0005 flagged "no API access yet" — all assumptions):**

- **Base URL pod** — default `https://na4.docusign.net/restapi/v2.1`; confirm the
  account's pod via the OAuth `/oauth/userinfo` endpoint (`accounts[].base_uri`).
- **Token lifetime** — DocuSign OAuth access tokens expire (~8 h). The stored secret is
  an operator-provisioned token; if live runs need unattended freshness, file the
  follow-up for a JWT-grant flow (integration key + RSA key in the SecretStore) — the
  connect layer already takes the token as a parameter, so only the task changes.
- The `envelopes` / `nextUri` paging property names and the `recipients.signers` shape.
- The bronze table's own columns were migrated as assumptions too (migration 0038).

## Endpoint & paging

| What | Endpoint |
| --- | --- |
| Envelope changes since a date | `GET {base}/accounts/{accountId}/envelopes?from_date={ISO}&include=recipients&count=100` |

Paging: items under `envelopes`, next page under `nextUri` (**relative** path, resolved
against the base by `Invoke-ImperionDocuSignRequest`). Retry/backoff via the shared
`Invoke-ImperionRestWithRetry` (429/503 honored).

## Cadence & incrementality

Daily (`scheduled-tasks/README.md` registry). Incremental window
`IMPERION_DOCUSIGN_SINCE_DAYS` (default 7); `0` = full backfill from `2000-01-01`.
DocuSign's `from_date` filters on envelope *change*, so a window re-pull is safe — the
upsert is change-detected (`content_hash`), unchanged envelopes are not rewritten.

## Fields (flat columns mirror migration 0038 exactly)

| Bronze column | Source field |
| --- | --- |
| `subject` | `emailSubject` |
| `status` | `status` (sent/delivered/completed/declined/voided, verbatim) |
| `account_ref` | first `recipients.signers[].email` |
| `sent_at` | `sentDateTime` |
| `completed_at` | `completedDateTime` |

Everything else the API returns survives losslessly in `raw_payload` (bronze rule,
CLAUDE.md §5). Envelope **documents are not downloaded** — metadata only; no document
content, no PII beyond signer emails (provenance-stamped, lawful-basis guardrail §8).

## Cmdlets

- `Invoke-ImperionDocuSignRequest` — connect: bearer + `nextUri` paging.
- `Get-ImperionDocuSignEnvelope` — get: secrets from SecretStore, flatten to the
  bronze envelope (source `docusign`, external id = `envelopeId`).
- `Set-ImperionDocuSignContractToBronze` — post: `Invoke-ImperionBronzePost` adapter,
  `-ColumnSet` projection to the exact migration-0038 columns, change-detected upsert.
- Task: `scheduled-tasks/docusign/envelopes.task.ps1` (daily, gated).
