# Integration — M365 communications: cross-org mail, Teams chats, Teams meetings

**Purpose.** Land Imperion↔client communications in bronze so the silver `interaction`
timeline and the gold knowledge layer see the lead loop (issue #100, v1 gate 6 —
frontend ADR-0057). The collectors apply the cross-org noise filter
(`Test-ImperionCrossOrgComm`) so ONLY Imperion↔client traffic is kept — internal chatter
never lands.

## Pipeline (CLAUDE.md §6 — straight to Postgres, IT Glue skipped)
| Entity | Get (built earlier) | Post (issue #100) | Bronze table (frontend migration 0065) | Source |
| --- | --- | --- | --- | --- |
| Mail | `Get-ImperionM365Mail` | `Set-ImperionM365MailToBronze` | `m365_mail_messages` | `m365_email` |
| Teams chats | `Get-ImperionM365TeamsChat` | `Set-ImperionM365TeamsChatToBronze` | `m365_teams_chats` | `m365_teams` |
| Teams meetings | `Get-ImperionM365TeamsMeeting` | `Set-ImperionM365TeamsMeetingToBronze` | `m365_teams_meetings` | `m365_teams` |

Flat columns mirror the collectors 1:1 with one rename: the Teams collectors' `user`
flat column lands in **`user_upn`** (`user` is a reserved keyword; the writers add the
renamed property, the original survives in `raw_payload`). Standard envelope, PK
`(tenant_id, source, external_id)`, change-detected upsert via the issue-#105 scaffold.

## Auth — the module's Graph connection
Same cert-SP app-only token as every other m365 collector (`Get-ImperionGraphToken`),
single-tenant against the Imperion company tenant (Mark's 2026-06-11 authorization;
GDAP `ClientTenant` mode exists in the collectors but fan-out is deferred).

**Teams protected-API gate:** `/users/{id}/chats` (and chat messages) are Microsoft
**protected APIs** — application-permission access requires Microsoft's approval form
(~1 week turnaround) on top of the permission grant. **The mail path goes first**;
the Teams chat task stays gated (its run fails loudly at the Graph call and the catch
logs + exits cleanly) until approval lands. Meeting/calendar reads are regular
permissions (Calendars.Read) — not protected-API gated.

## Gates (all fail soft — log + clean exit, never crash the schedule)
1. **Env config:** `IMPERION_M365_MAILBOXES` (mail) / `IMPERION_M365_USERS` (Teams) +
   `IMPERION_M365_CLIENT_DOMAINS` (the cross-org filter input). Unset → Warn + exit.
2. **Migration 0065 prod apply:** merged in the frontend repo (ImperionCRM#182 /
   PR #202) but the orchestrator batches the prod apply — until then the upsert fails
   loudly and the task's catch gates it. No local-pipeline change needed after apply.
3. **(Teams chats only)** Microsoft protected-API approval, above.

## Cadence & windows (scheduled-tasks/README.md)
- `m365/mail` hourly; look-back `IMPERION_M365_MAIL_SINCE_DAYS` (default 7).
- `m365/teams-chat` hourly (chat list API has no server-side date filter; the
  change-detected upsert keeps re-runs cheap).
- `m365/teams-meeting` every 4h; look-back `IMPERION_M365_MEETING_SINCE_DAYS`
  (default 30).

## Provenance & consent
Rows are stamped source/collected_at per the envelope; communications data feeds the
timeline/dossier only — having a thread is **never** consent to contact (front-end
consent gate; cloud Pipeline CLAUDE.md §5).
