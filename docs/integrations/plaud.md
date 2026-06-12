# Integration — Plaud recordings → bronze `plaud_recordings` → silver `meeting` (issue #72)

Ingests **Plaud recordings** (in-person meeting capture: AI note/summary, action items,
speaker transcript) so meetings land in the communications timeline. Target chain:
PROPOSED bronze `plaud_recordings` → silver `meeting` (front-end migration 0028:
`plaud_summary` / `transcript_ref`, 1:1 with `interaction(kind=meeting)`).

Pure CRM/comms data → flattens straight to Postgres; no IT Glue step (ADR-0006).

## Plaud is an MCP server, not a REST API (locked design, issue #72 comment 2026-06-10)

- Endpoint `https://mcp.plaud.ai/mcp`, JSON-RPC 2.0 `tools/call`.
- Tools: `list_files`, `get_file` (presigned audio URLs — NOT pulled; we never ingest
  audio), `get_note` (AI summary/action items), `get_transcript` (timestamps + speakers).
- The live agent-tools half is a separate `ImperionCRM_Backend` issue; THIS is the
  scheduled ingestion half.

## Credential (GATED) — per-user OAuth, browser-granted

| Secret (SecretStore, CLAUDE.md §2) | Name key (`config/secret-names`) | Holds |
| --- | --- | --- |
| `plaud-oauth-token` | `PlaudOAuthToken` | OAuth access token — raw string OR a JSON blob `{ "access_token", "refresh_token", "expires_at" }` |

Mark performs the one-time browser OAuth on the host box and stores the token. **Refresh
can break and need a human re-login**, so the rule is FAIL LOUDLY: the connect layer
throws on a JSON-RPC error, the get layer lets it propagate, and the task catches → Warn
log → clean exit. The schedule never crashes; a re-login + next run converges.
Unattended refresh (using the stored refresh_token before each run) is a follow-up once
the live token shape is confirmed.

## SCHEMA GATE — bronze table does not exist yet

`plaud_recordings` needs a **front-end migration** (schema owned there, ADR-0017).
Proposed DDL (standard local-pipeline envelope — submit via the schema handoff):

```sql
CREATE TABLE IF NOT EXISTS plaud_recordings (
  title text, started_at text, duration_seconds text, summary text,
  action_items text, transcript text,
  tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
  collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
  PRIMARY KEY (tenant_id, source, external_id)
);
-- + GRANT SELECT, INSERT, UPDATE ON plaud_recordings TO "imperion-localpipeline";
```

**Meeting feed (issue #72 acceptance, follow-up):** the bronze→silver merge that creates
`interaction(kind=meeting)` + `meeting` rows (platform `plaud`, `plaud_summary`,
`transcript_ref`) keyed on the recording id needs the bronze table first plus
INSERT/UPDATE grants on `interaction`/`meeting` — tracked as its own sub-issue so the
attendee→contact matching gets proper review.

## Cadence & fields

Daily. Flat columns (everything else lossless in `raw_payload`): `title` · `started_at` ·
`duration_seconds` · `summary` (note) · `action_items` (joined) · `transcript` (text
form; the structured speaker/timestamp transcript stays in raw_payload). Audio is never
downloaded. PII note: transcripts are personal data — provenance-stamped rows, and the
consent/lawful-basis guardrail (§8) applies before any outbound use.

## Cmdlets

- `Invoke-ImperionPlaudRequest` — connect: JSON-RPC tools/call, bearer auth, unwraps
  structuredContent / text-JSON content blocks; throws on JSON-RPC errors.
- `Get-ImperionPlaudRecording` — get: list_files → per file get_note (+ get_transcript
  unless `-SkipTranscript`), one flat row per recording (source `plaud`).
- `Set-ImperionPlaudRecordingToBronze` — post: `Invoke-ImperionBronzePost` adapter,
  `-ColumnSet` projection, change-detected upsert.
- Task: `scheduled-tasks/plaud/recordings.task.ps1` (daily, double-gated: token + pending
  migration).

## Assumptions to confirm on first authenticated pull

- Tool argument names (`file_id`) and the list/note/transcript result shapes
  (`files[].id/title/startedAt/duration`, `summary`/`actionItems`, transcript `text`).
- Whether results arrive as `structuredContent` or text content blocks.
- The stored token's exact blob shape (raw vs JSON) and its refresh story.
