# m365 — Microsoft Graph (mail, Teams, users, devices)

Code: [`src/ImperionPipeline/Public/m365/`](../../src/ImperionPipeline/Public/m365)

**Auth:** the certificate-backed Entra app (the *Imperion Client Onboarding* app) authenticates
in the partner tenant and reads each client tenant's Graph through its **GDAP** relationship
(read-only). The app is a member of all GDAP groups and holds read permissions for the objects
below. Per-tenant isolation is absolute — every row is tagged with its owning tenant.

**The most verbose area** because of the object variety (mailboxes, chats, meetings, users,
devices) and the per-mailbox fan-out for communications.

## connect
| Function | Purpose |
| --- | --- |
| `Invoke-ImperionGraphRequest` ✓ | GET a Graph collection, follow `@odata.nextLink`, return all items. Optional `$select`. The shared read primitive for every `get` below. |
| `Invoke-ImperionGraphSearch` ☐ | `$search`/`$filter` helper for mail & chat message queries (the communication filter). |

## get (planned — per object)
| Function | Object | Graph surface | Filter |
| --- | --- | --- | --- |
| `Get-ImperionM365User` ☐ | Users | `/users` | enabled members |
| `Get-ImperionM365Device` ☐ | Devices | `/deviceManagement/managedDevices`, `/devices` | → `m365_devices` |
| `Get-ImperionM365Mail` ☐ | Emails | `/users/{id}/messages` | **communication filter** (below) |
| `Get-ImperionM365TeamsChat` ☐ | Teams chats | `/users/{id}/chats`, `/chats/{id}/messages` | **communication filter** |
| `Get-ImperionM365TeamsMeeting` ☐ | Teams meetings | `/users/{id}/onlineMeetings`, `/events` | **communication filter** |

## post (planned — per object, per target)
`Set-ImperionM365*ToBronze` ☐ (Postgres `m365_*` bronze) · device/user docs into IT Glue ☐.

## Communication filter (noise control)

Collect **only cross-org Imperion↔client** mail/chat/meetings:

- **Imperion tenant** (`@imperionllc.com`): keep items where **any other participant's domain ∈
  the known-client domain set** (derived from silver `account` + the tenant map).
- **Client tenant** (GDAP): keep items where **any participant is `@imperionllc.com`**.

Drop internal-only threads. Match on participant SMTP domain (sender + recipients for mail;
members for chats; attendees + organizer for meetings). These land on the silver `interaction`
timeline as `m365_email` / `m365_teams` (data-model Diagram 1/5).

## Data-model targets
`m365_devices` (bronze, Diagram 6b) · silver `interaction` (`source = m365_email|m365_teams`)
→ `meeting` (`platform = teams`) for meetings · `external_identity` (provider `m365`).

## Cadence
Communications hourly; users/devices daily. See [`../../scheduled-tasks/`](../../scheduled-tasks).
