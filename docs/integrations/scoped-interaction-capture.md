# Integration — Home-tenant interaction capture (mail / Teams chat / Teams meetings)

**Purpose.** Land the account-history interaction loop (mail + Teams chat + Teams meetings) in
bronze `m365_email` / `m365_teams` / `m365_teams_meetings` (issue #199 / epic #194 child E,
ADR-0022). These are the **message-grain** counterparts to the broad cross-org collectors
(`Get-ImperionM365Mail` → `m365_mail_messages`, migration 0065); both coexist.

> **Capture model (front-end ADR-0126 / FE #1366, this repo's #380).** Client communications
> are pulled from **Imperion's OWN tenant** (client tenants do NOT hold Mail.Read / Chat.Read /
> Calendars.Read) and are filtered to DB clients **LATER, at the silver layer** (front-end
> #1369), against `account_domain` + onboarded contacts. **These collectors therefore do NOT
> filter at collection.** This is the fix for the 0-row prod state (#380): the previous
> collection-time client filter dropped every message/chat/meeting whenever the silver client
> set (`account_domain`) was empty — which it is in prod — so a fully-consented collector still
> landed nothing. We over-collect at bronze and narrow at silver (CLAUDE.md §5 bronze rule).
> The allowlist below now selects WHICH MAILBOXES / PRINCIPALS to pull, not which items to keep.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get | Post | Bronze table (frontend migration) | Source |
| --- | --- | --- | --- | --- |
| Mail | `Get-ImperionScopedInteractionMail` | `Set-ImperionScopedInteractionMailToBronze` | `m365_email` (0120) | `m365_email` |
| Teams chat | `Get-ImperionScopedInteractionTeams` | `Set-ImperionScopedInteractionTeamsToBronze` | `m365_teams` (0120) | `m365_teams` |
| Teams meetings | `Get-ImperionM365TeamsMeeting` | `Set-ImperionM365TeamsMeetingToBronze` | `m365_teams_meetings` (0065) | `m365_teams` |

Standard lossless envelope, PK `(tenant_id, source, external_id)` (external_id = the Graph
message id), change-detected upsert via the issue-#105 `Invoke-ImperionBronzePost` scaffold
(`-ColumnSet` projection — a future collector field can never break the insert; extras survive
in `raw_payload`). `m365_email` flat columns: message/conversation id, subject, preview,
from_address, to_recipients, direction, sent_at, has_attachments, mailbox_owner. `m365_teams`:
message/conversation id, preview, from_user, participants, direction, message_type, sent_at,
has_attachments, captured_user.

## Scoping — at SILVER, not at collection (ADR-0126)
There is **no collection-time client filter**. Every message/chat/meeting from the allowlisted
mailboxes/principals lands in bronze. The client-scoping decision (keep only direct
client↔employee history; drop internal/non-client traffic) is owned by the **silver client-comms
filter in the front end (FE #1369)**, run against `account_domain` + onboarded contacts.

Historical note: the previous `Test-ImperionScopedInteraction` /
`Resolve-ImperionClientContactSet` collection-time predicate (kept only allowlisted-principal ↔
known-client items) is retired from the collector path by #380; it is no longer wired in (the
helper functions and their unit tests remain in the repo for potential reuse by the silver
filter, but no collector calls them). The lawful-basis guardrail (CLAUDE.md §8) still holds:
the data is captured for the company's own account-history second brain; having a thread is
**never** consent to contact, and the silver filter narrows it to real clients.

## The allowlist is CONFIG, not code
The mailboxes/principals whose communications are captured live in a machine config json —
**not hardcoded**, so the set changes WITHOUT a code release:

- Path (default): `%ProgramData%\Imperion\interaction-allowlist.json`
  (override: `$env:IMPERION_INTERACTION_ALLOWLIST`, or `-AllowlistPath` for test/on-demand).
- Shape (see `config/interaction-allowlist.example.json`):
  ```json
  { "principals": [ { "upn": "derek@imperionllc.com" }, { "upn": "mark@imperionllc.com" } ] }
  ```
  Only `upn` is read (case-insensitive); `displayName` / `notes` document the file for a human
  editor and are ignored.
- v1 set = Derek Rankin + Mark Connelly. The real file is **NOT committed** (UPNs are employee
  identifiers, `.gitignore`); only the `.example.json` with placeholder UPNs ships.
- **No allowlist / empty allowlist → DORMANT:** the collector logs and returns, capturing
  nothing (never wide-open).

## Auth — the module's read-only Graph app (no new app/secret)
Reuses the cert-SP app-only Graph token (`Get-ImperionGraphToken`, ADR-0002 / pipeline
ADR-0018 onboarding-app read-only grants). **No new app registration, no write scope, no new
SecretStore secret.** Single-tenant against the Imperion company tenant by default; per-client
onboarding-app fan-out (pipeline ADR-0018) is supported via `-TenantId` but deferred.

**Teams protected-API gate:** `/users/{id}/chats` + chat messages are Microsoft **protected
APIs** — application-permission access requires Microsoft's approval form (~1 week) on top of
the permission grant. **The mail path goes first;** the Teams task stays gated (Graph call
fails loudly, the task's catch logs + exits cleanly) until approval lands.

## Gates to LIVE (all fail soft — log + clean exit, never crash the schedule)
1. **Allowlist json** provisioned at `%ProgramData%\Imperion\interaction-allowlist.json`.
2. **Graph Mail.Read** consent for the principal mailboxes (mail) / chat read consent (Teams).
3. **(Teams only)** Microsoft protected-API approval for `/chats` + messages.

Migration `0120` (`bronze_batch_b`, `m365_email` / `m365_teams`) is **already merged +
prod-applied + verified** — the schema gate is CLEAR; the collectors are deploy-ahead/dormant
on consent + config only.

## Cadence & windows (scheduled-task-registry.md)
- `m365/scoped-interaction-mail` hourly; look-back `-SinceDays` (default 7).
- `m365/scoped-interaction-teams` hourly (chat list API has no server-side date filter; the
  change-detected upsert keeps re-runs cheap).
- `m365/teams-meeting` every 4h; gated only on `IMPERION_M365_USERS` (which calendars to pull —
  the `IMPERION_M365_CLIENT_DOMAINS` filter was removed by #380); look-back
  `IMPERION_M365_MEETING_SINCE_DAYS` (default 30).

## CONFIRM-BEFORE-LIVE
The Graph `/messages` + `/chats/{id}/messages` field names, the `receivedDateTime` filter, the
chat-member email path, and the inbound/outbound direction heuristic are modeled from the
documented API and UNVERIFIED until consent lands. Each flat column leads with the documented
name; an unmatched value lands NULL and nothing is lost (full `raw_payload`). Confirm the live
shapes before flipping the tasks on.

## Provenance, PII & logging
Rows are envelope-stamped `source`/`collected_at`. The structured logs record **counts only —
never subjects, addresses, message content, or principal identity** (CLAUDE.md §8). Fixtures in
the Pester tests are **synthetic** — no real client data or employee identity in code/tests.

## Silver / OKF
This collector lands **bronze only** — `m365_email` / `m365_teams` are landing tables (FE
`0120`), not silver entities, so **no OKF concept-file / coverage-matrix change is required
here** (system CLAUDE.md §11). When the silver `interaction` entity is later wired to consume
these (its source-of-record / join paths), that decision is **proposed back to the front end**
via an `ImperionCRM` issue — not authored cross-repo here.
