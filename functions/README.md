# `functions/` — function architecture & catalog (docs)

> **This tree is documentation only.** The executable PowerShell lives in the installed
> module under [`src/ImperionPipeline/Public/`](../src/ImperionPipeline/Public). Each area
> folder here mirrors a module sub-folder one-to-one and catalogs the functions in it —
> what exists, what's planned, the auth model, the data-model targets, and the polling
> cadence. Read [`../CLAUDE.md`](../CLAUDE.md) first.

## The three-layer model (build order)

Every integration is built in the same three layers, **in this order**, so downstream work
can reuse the layer beneath it:

| Layer | Folder | What it is | Reuse |
| --- | --- | --- | --- |
| **1 · connect** | `<area>/connect/` | Reusable **connection / auth / paged-request** utilities for one API. Mint/refresh the token, detect the zone, page the collection with 429/503 backoff, return raw objects. | Built **first**. Every `get` reuses it. |
| **2 · get** | `<area>/get/` | **Per-object collectors.** One function per object type (companies, contacts, devices, tickets, …). Calls the `connect` layer, **flattens to a `[PSCustomObject]` flat table** (`ConvertTo-ImperionFlatObject`), returns rows. No writes. | Built **second**. Scheduled tasks + `post` reuse it. |
| **3 · post** | `<area>/post/` | **Per-object, per-API writers.** Take a flat table and write it — to Postgres bronze (`Invoke-ImperionBronzeUpsert`) and/or document into IT Glue. Idempotent upserts. | Built **last** (lowest priority). |

Cross-cutting helpers that aren't API-specific (logging, hashing, flatten, DB connection +
query, SecretStore unlock, token acquisition, task registration) live in
[`utility/`](./utility).

## Areas

| Area | Code | API / source | Auth | Notes |
| --- | --- | --- | --- | --- |
| [utility](./utility) | `Public/utility/` | — (cross-cutting) | — | Logging, hashing, flatten, DB, SecretStore, token, task registration |
| [m365](./m365) | `Public/m365/` | Microsoft Graph | Cert app, GDAP per tenant | Mail, Teams chat/meetings, users, devices — **most verbose** (see filter rule below) |
| [azure](./azure) | `Public/azure/` | Azure Resource Manager | Cert app, `Reader` | Subscriptions, resources, Sentinel |
| [autotask](./autotask) | `Public/autotask/` | Autotask REST (PSA) | API user + secret + integration code, zone-detected | Companies, contacts, contracts, tickets |
| [itglue](./itglue) | `Public/itglue/` | IT Glue REST | API key (read) + write key | Documentation + relationship hub (read **and** write) |
| [telivy](./telivy) | `Public/telivy/` | Telivy API | Bearer token | Security assessments / analytics (assessment artifacts) |
| [darkwebid](./darkwebid) | `Public/darkwebid/` | Dark Web ID (ID Agent) | OAuth client credentials | Compromise / credential-exposure monitoring |
| [posture](./posture) | `Public/posture/` | Graph + ARM (security estate) | Cert app | Service principals, Secure Score, CA/Intune/Defender policies + golden-state drift |
| [kaseya](./kaseya) | `Public/kaseya/` | Autotask + KQM (Kaseya stack) | per-source keys | Bulk CRM/support bronze loader (proposals, contracts, tickets) |

## Scheduled tasks compose these micro-functions

Each `(source, entity)` job is **one scheduled task** (CLAUDE.md §1) whose task file stays
short — it imports the module, initializes context, then calls one `get` + one `post`. The
task files and their **polling cadence** live in [`../scheduled-tasks/`](../scheduled-tasks).
Keeping the orchestration in the task file (not the functions) is what lets a function be
reused by a backfill, an ad-hoc run, and the schedule alike.

## The m365 communication filter (noise control)

M365 mail/Teams collection is scoped to **platform-relevant** communications only — the goal
is the conversations that matter to the engagement, not every message in every mailbox:

- **For the Imperion tenant (`@imperionllc.com`)** → collect emails, Teams chats, and Teams
  meetings **with a client domain** on the other side (any participant whose domain maps to a
  known client `account`/tenant).
- **For each client tenant (GDAP)** → collect emails, Teams chats, and Teams meetings **with
  `@imperionllc.com`** on the other side.

Either way the filter keeps **only cross-org Imperion↔client communication** and drops
internal-only noise. The matching domain set is derived from the silver `account` / tenant
map. See [m365/README.md](./m365) for the exact Graph queries and filter predicate.
