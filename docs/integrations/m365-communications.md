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
per-client onboarding-app fan-out to client tenants — pipeline ADR-0018 — is supported
by the collectors but deferred).

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

## Silver merge — `client_communication` (ADR-0126, LP #395)
`Invoke-ImperionClientCommunicationMerge` folds the three comms bronze tables into the
silver **`client_communication`** ledger (front-end migration 0211, epic
ImperionCRM#1366) — the unified, **client-scoped** comms history (email + teams_chat +
teams_meeting; the `social_dm` channel is the sibling sink, LP #383). Merge co-locates
with ingestion (ADR-0026); idempotent, set-based, run AFTER the collectors.

**The filter rule (the entity's defining contract).** For each bronze row the merge
gathers all participant addresses (mail: from+to+cc; chat: members; meeting:
organizer+attendees), splits the Imperion side from the non-Imperion side by domain
(`-ImperionDomain`, default `imperionllc.com`), and resolves the client side to ONE DB
account by, in precedence order:
1. exact onboarded-contact email match (`contact.email`) → stamps `account_id` +
   `contact_id` when **exactly one** distinct contact resolves;
2. else `account_domain.domain` match → stamps `account_id` (contact_id NULL) when
   **exactly one** distinct account resolves.

A row resolving to no single account is **dropped** (the gate) — internal-only threads and
ambiguous/unknown counterparties never land. So the bronze cross-org filter
(`Test-ImperionCrossOrgComm`) is the coarse pass; THIS merge is the precise per-account
attribution (FE #1369's silver concern).

**PII-minimal (ADR-0126).** subject/topic only — **no message bodies** (the bronze doesn't
collect them); `snippet` stays NULL for the M365 channels. `direction` = inbound
(client→employee) / outbound (employee→client), derived from the sender (mail) / organizer
(meeting); a chat carries no per-row sender so it lands `inbound` by convention.
Idempotent upsert on `UNIQUE (channel, source_system, external_id)` with `content_hash`
change detection (replace-from-source, ADR-0026). `data_class = client_pii`.

**Grants:** migration 0211 grants `client_communication` SELECT,INSERT,UPDATE to
`imperion-localpipeline` — no grant gap (unlike `social_engagement`/#357). GATED: 0211 is
prod-applied (the #1366 wave); the merge writes whatever bronze exists and the upsert
fails loudly until 0211 is present. **Registered by `Register-ImperionTask` as
`\Imperion\Imperion-ClientCommunicationMerge` @ hourly (AFTER the mail/chat collectors)**
— operator: re-run `Register-ImperionTask` once, then `Start-ScheduledTask -TaskName
'Imperion-ClientCommunicationMerge' -TaskPath '\Imperion\'` to run on demand.

## Provenance & consent
Rows are stamped source/collected_at per the envelope; communications data feeds the
timeline/dossier only — having a thread is **never** consent to contact (front-end
consent gate; cloud Pipeline CLAUDE.md §5).
