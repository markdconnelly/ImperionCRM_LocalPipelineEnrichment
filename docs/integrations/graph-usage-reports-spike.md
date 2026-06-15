# Spike — Microsoft Graph usage reports (`Reports.Read.All`) for client analytics

**Status:** SPIKE / assessment only — no production collector, no schema, no live data pull.
**Issue:** #144. **Trigger:** Mark's per-source review 2026-06-12 — _"not sure how this maps,
but if it provides value to the client analytics, worth exploring."_
**Recommendation:** **DEFER** (build later, narrowly) — see [§7](#7-recommendation).

> This is an assessment document, not an integration spec. Nothing here is wired to a
> scheduled task. Any live pull is **Mark-gated** (a new GDAP role + admin consent, §3/§5).
> No row-level data, no PII, and no client identifiers appear in this doc (system CLAUDE.md
> §8; this repo CLAUDE.md §8).

---

## 1. What these reports are

Microsoft Graph exposes a **`reports` namespace** that returns _aggregated_ tenant activity
and adoption metrics for Microsoft 365 workloads — the same numbers that drive the M365 admin
center "Usage" dashboards. They are **derived, pre-aggregated rollups** (daily snapshots and
trailing-window summaries: D7 / D30 / D90 / D180), **not** the underlying mail/Teams/file
events. They are distinct from:

- **`m365-communications.md`** (this repo) — actual Imperion↔client mail/Teams _content_ for
  the interaction timeline. Usage reports carry **no message bodies, no recipients, no file
  contents** — only counts and last-activity dates.
- **`secure-score.md` / posture collectors** — security configuration, not activity/adoption.

Two report families:

| Family | Endpoint shape | Returns |
| --- | --- | --- |
| **Activity / usage reports** | `GET /reports/getXxxYyy(period='D30')` | CSV (default) or JSON; per-workload activity rollups |
| **Adoption / usage report (Viva-style)** | `GET /reports/...` adoption set | Active-vs-enabled adoption framing |

---

## 2. Endpoint catalog (Graph v1.0, `reports` namespace)

Selected high-signal endpoints (function-style; `period` ∈ `D7|D30|D90|D180`, or a single
`date` for some). All return CSV by default; append `?$format=application/json` for JSON.
This is a representative map, not exhaustive.

| Workload | Endpoint (function) | Signal |
| --- | --- | --- |
| **Tenant licensing** | `getOffice365ActiveUserDetail(period)` / `getOffice365ActiveUserCounts(period)` | Per-user / aggregate product-by-product activity (Exchange, OneDrive, SharePoint, Teams, Yammer) |
| **Tenant services** | `getOffice365ServicesUserCounts(period)` | Active vs inactive users per service |
| **Email activity** | `getEmailActivityUserCounts(period)` / `getEmailActivityCounts(period)` | Send / receive / read volumes (counts only) |
| **Mailbox usage** | `getMailboxUsageDetail(period)` / `getMailboxUsageStorage(period)` / `getMailboxUsageQuotaStatusMailboxCounts(period)` | Storage consumed, quota state, item counts |
| **Teams activity** | `getTeamsUserActivityUserDetail(period)` / `getTeamsUserActivityCounts(period)` | Messages, meetings, calls per user/aggregate |
| **Teams device** | `getTeamsDeviceUsageUserCounts(period)` | Windows / Mac / web / mobile split |
| **OneDrive** | `getOneDriveUsageAccountCounts(period)` / `getOneDriveActivityUserDetail(period)` | Active accounts, files viewed/edited, storage |
| **SharePoint** | `getSharePointSiteUsageDetail(period)` / `getSharePointActivityUserDetail(period)` | Site storage, file activity, active site counts |
| **Activations** | `getOffice365ActivationsUserDetail` | Office desktop activations per user / device / platform |
| **Browser/app usage** | `getM365AppUserDetail(period)` / `getM365AppUserCounts(period)` | Which apps/platforms users actually run |

**Privacy-name flag (critical, see §6):** when the tenant has the admin-center setting
**"display concealed user, group, and site names"** enabled, the `...Detail` endpoints return
**pseudonymized identifiers** (e.g. `User 00012`) instead of UPNs. The `...Counts` /
`...Storage` / aggregate endpoints are unaffected because they carry no identity at all.

---

## 3. Scope & consent requirements

- **Application permission:** `Reports.Read.All` (Microsoft Graph, **application**,
  read-only). Admin-consent required. This is a **net-new grant** beyond the read-only set
  the cert app holds today, so it is a **human-approval gate** (this repo CLAUDE.md §2/§8 —
  "any new capability is an explicit, documented, human-approved grant").
- **Cert app-only token**, scope `https://graph.microsoft.com/.default` — same shape as
  `secure-score.md` / every posture collector; reuse `Get-ImperionGraphToken`.
- **Per-client (GDAP) reach:** these are **tenant-scoped** reports. For client analytics
  the app must read **each customer tenant** through the delegated relationship (GDAP, §3 of
  CLAUDE.md). `Reports.Read.All` must be in the **GDAP role set** for each client — another
  **GDAP-widening security event** (CLAUDE.md §3/§8). Partner-tenant-only (Imperion's own
  tenant) needs no GDAP change but gives only Imperion's own numbers, not client analytics.
- **No protected-API gate** (unlike Teams `/chats`): usage reports are regular application
  permissions, so no Microsoft approval-form turnaround.

**Net consent cost to deliver _client_ analytics:** `Reports.Read.All` granted to the app
**and** added to the per-client GDAP role — two approval gates, both Mark's call.

---

## 4. Client-analytics value (what it would add)

Mapped against what the silver/gold layers already know and what the front-end analytics
surfaces (BI hub, ADR-0062) could consume:

**High value (genuinely new signal):**
- **Adoption / license-waste detection.** `getOffice365ActiveUserDetail` +
  `getOffice365ServicesUserCounts` reveal **assigned-but-inactive** licenses per client — a
  direct MSP up-sell/right-size lever and a recurring QBR talking point. The CRM has license
  _assignment_ (via Entra) but not _activity_; this is the gap.
- **Workload health / churn-risk leading indicator.** Falling Teams/email/OneDrive activity
  trends are an early "client disengaging" signal the orchestrator agent could fold into
  account-health scoring.
- **Storage/quota foresight.** Mailbox/OneDrive/SharePoint storage trending toward quota =
  proactive ticket / expansion conversation before the client hits a wall.

**Moderate value (nice, overlaps existing):**
- Teams device-usage split (platform mix) — informs endpoint posture, partly visible via
  Intune device data already collected.
- M365 app usage — which apps are actually run; supports adoption coaching.

**Low / no value here:**
- Email/Teams _activity counts_ duplicate, more coarsely, what the `m365-communications`
  interaction timeline already captures with real content — usage reports add nothing the
  timeline lacks except aggregate trend convenience.

**Where it lands (if built):** aggregate, trend-shaped, per-tenant → a **gold knowledge
object** ("client M365 adoption posture") the agent reasons over, and/or a BI-hub trend
strip. It is **adoption/health analytics**, not a CRM entity — it does **not** create or
merge a silver entity, so no OKF concept-file impact (CLAUDE.md §11).

---

## 5. Cadence, shape, idempotency (if built)

- **Cadence:** reports refresh **daily** server-side but lag **~24–48h** and a value
  **stabilizes only after the period window closes** — so a row can change for a day or two
  after first appearance. Poll **daily**, store the snapshot keyed by `(tenant, report,
  period, snapshot_date)`, upsert on content hash (CLAUDE.md §6 idempotency).
- **Format:** request **JSON** (`?$format=application/json`) to flatten directly into the
  repo's flat-`[PSCustomObject]` table currency (CLAUDE.md §4) rather than parsing CSV.
- **Bronze rule:** over-collect the raw payload, narrow at silver/gold (CLAUDE.md §5). Note
  the `...Detail` per-user rows are **high cardinality** (one row per user per tenant per
  snapshot) — favor the `...Counts` / aggregate endpoints unless per-user is the point, to
  control volume and PII exposure (§6).

---

## 6. PII concerns (the deciding constraint)

This is where usage reports get heavy and why the recommendation is **defer, then build
narrow**:

1. **`...Detail` endpoints are personal data.** Per-user UPN + per-user activity/last-active
   dates are **employee behavioral monitoring** of the _client's_ staff. Holding "who is
   active / inactive / how much they email" per named user is a meaningful privacy and
   lawful-basis question, not just a CRM field. It collides head-on with the system's
   lawful-basis + provenance guardrail (CLAUDE.md §8) and the "having data is never consent"
   line.
2. **Pseudonymization defeats the per-user value anyway.** If the tenant has concealed-names
   enabled (a hardening default many orgs set), the `...Detail` rows are `User 00012` — so
   the per-user signal is _both_ the riskiest _and_ often unusable. The valuable,
   defensible signal is the **aggregate `...Counts` / `...Storage`** layer, which carries
   **no identity**.
3. **Cross-tenant isolation** (CLAUDE.md §3) — every row must be tenant-tagged; no
   cross-tenant query path. Standard, but mandatory.
4. **Doc/issue hygiene** — never copy a sample row with real UPNs/site names into any issue,
   PR, or doc (CLAUDE.md §8). Sample shapes against the Imperion tenant only, and redact.

**Posture-clean subset:** **aggregate counts/storage only, no `...Detail` per-user rows.**
That subset is non-PII, still delivers the high-value adoption/health/storage signals (§4),
and sidesteps the lawful-basis problem entirely.

---

## 7. Recommendation

**DEFER — then build a narrow, aggregate-only collector when prioritized.**

Reasoning:
- The **high-value** signals (license-waste, adoption/health trend, storage foresight) are
  real and otherwise-missing — this is **worth building eventually**.
- But the value sits in the **aggregate, non-PII** endpoints; the per-user `...Detail` rows
  are the privacy-heavy part **and** are frequently pseudonymized into uselessness, so the
  right build is **narrow** (counts/storage only) — which also keeps it posture-clean.
- It requires **two approval gates** (`Reports.Read.All` on the app + GDAP-role widening per
  client) and is **not on the v1 critical path** — v1 is the data loop and the
  expense/time/orchestration work. No reason to spend the GDAP-widening security event now.
- It creates **no silver entity** and **no schema migration** (gold knowledge object / BI
  trend only), so deferring costs nothing structurally.

**Defer, do not drop:** keep #144 closed-as-assessed with a follow-up filed so the signal
isn't lost.

### Proposed follow-up issue (to file when prioritized)

> **feat(posture): aggregate-only M365 usage-report collector → gold adoption posture**
> Build `Invoke-ImperionM365UsageSync` over the **aggregate** Graph report endpoints only
> (`getOffice365ServicesUserCounts`, `getOffice365ActiveUserCounts`,
> `getMailboxUsageStorage`, `getOneDriveUsageAccountCounts`,
> `getSharePointSiteUsageDetail` storage cols, `getTeamsUserActivityCounts`) — JSON format,
> daily cadence, snapshot-keyed idempotent upsert. **Explicitly exclude** all `...Detail`
> per-user endpoints (PII, §6). Feeds a gold "client M365 adoption posture" knowledge object
> for account-health / license-waste analytics (ADR-0062 BI hub consumer).
> **Gates (Mark):** (1) `Reports.Read.All` application consent on the cert app; (2) add
> `Reports.Read.All` to the per-client GDAP role set. (3) Front-end migration for the bronze
> usage-report table(s) — propose in `ImperionCRM` (CLAUDE.md §5/§6), claim the migration
> number at merge (system §10.3).

---

## 8. Optional gated probe stub

A read-only enumeration helper to sample report **shapes** (column names, period behavior)
against the **Imperion tenant only** — useful when the follow-up is picked up. **Not wired
to any scheduled task; fails closed until the grant exists.** Sketch (not committed as a
module cmdlet — it lives here as a reference):

```powershell
# REFERENCE ONLY — do not register as a task. Requires Reports.Read.All (Mark-gated).
# Samples aggregate report SHAPES against the Imperion tenant. Redact before sharing output.
function Invoke-ImperionUsageReportProbe {
    [CmdletBinding()]
    param([ValidateSet('D7','D30','D90','D180')][string]$Period = 'D30')

    # Gate: refuse unless the grant is present (probe stays dormant otherwise).
    if (-not $env:IMPERION_ENABLE_USAGE_PROBE) {
        Write-Warning 'Usage-report probe disabled. Set IMPERION_ENABLE_USAGE_PROBE only after Reports.Read.All is consented (Mark-gated).'
        return
    }

    $token = Get-ImperionGraphToken            # cert app-only, .default scope (existing helper)
    $base  = 'https://graph.microsoft.com/v1.0/reports'
    # Aggregate-only by design (no ...Detail / no per-user PII, §6).
    $reports = @(
        "getOffice365ServicesUserCounts(period='$Period')",
        "getOffice365ActiveUserCounts(period='$Period')",
        "getMailboxUsageStorage(period='$Period')",
        "getOneDriveUsageAccountCounts(period='$Period')",
        "getTeamsUserActivityCounts(period='$Period')"
    )
    foreach ($r in $reports) {
        $uri = "$base/$r" + '?$format=application/json'
        $resp = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Method Get
        # Inspect SHAPE only — column names / row count. Never persist or log values here.
        [PSCustomObject]@{ report = $r; columns = ($resp.value[0].PSObject.Properties.Name -join ','); rows = $resp.value.Count }
    }
}
```

---

## 9. References
- This repo `CLAUDE.md` §2 (grant model / approval gates), §3 (GDAP read-only), §5/§6
  (bronze rule, schema-ownership, idempotency), §8 (lawful-basis posture).
- `docs/integrations/secure-score.md` — sibling read-only Graph collector pattern (auth shape).
- `docs/integrations/m365-communications.md` — the _content_ interaction collectors usage
  reports are distinct from.
- System `CLAUDE.md` §1 (schema owned by front end), §8 (read-only DB / no PII in artifacts),
  §10.3 (migration/ADR numbers claimed at merge), §11 (OKF — N/A here, no silver entity).
- Front-end ADR-0062 (BI hub — the analytics consumer of any future usage-report gold object).
