# ADR-0011: Quarterly Imperion Secure Score snapshots — daily-gated calendar quarters, parity-pinned score math

| Field | Value |
|---|---|
| **Status** | Accepted (2026-06-11) |
| **Issue** | #89 (sub-issue of #74) |
| **Cross-references** | frontend ADR-0051 §4/§5 (Score Model, snapshot specs) · frontend migration 0063 (`posture_snapshot`/`posture_snapshot_pillar`, append-only by grant) · this repo's ADR-0010 (posture silver bulk merge) |

## Context

Frontend ADR-0051 §5 locked immutable, per-account Posture Snapshots: composite, stored
letter grade, Score Model version, and one row per pillar, taken quarterly (calendar
quarters), on demand, and automatically when a Business Review is created. Migration
0063 landed the tables and enforced append-only **by grant** (pipeline roles hold
INSERT+SELECT only — verified against prod). The frontend's at-a-glance card ships the
live Score Model v1 math as a pure function (`src/lib/security/imperion-score.ts`) with
the explicit note that the snapshot job MUST reuse this math.

## Decision

`Invoke-ImperionPostureSnapshot` + the daily `Imperion-PostureSnapshot` task (03:40,
after the 03:20 posture merge so snapshots read the night's fresh rollups):

1. **Score math lives in a pure twin, parity-pinned.** `Get-ImperionSecureScore` is the
   PowerShell twin of the frontend's `imperion-score.ts` — same pillar normalizations
   (licensed-user-weighted m365; compliant/classified policy ratio; darkweb
   `max(0, 100 − 10×exposures)` with covered=false until a rollup exists), same
   composite (equal-weight mean over ALL model pillars, uncovered contribute 0), same
   rounding (stored composite to one decimal half-away-from-zero; grade banded from the
   UNROUNDED composite). The Pester suite mirrors the frontend's
   `imperion-score.test.ts` vectors case for case. **If one changes, change both.**
2. **Daily task, calendar-quarter gate, DB clock.** Task Scheduler has no native
   quarterly trigger, and a literal Jan-1 run is fragile (server off = quarter missed).
   The task fires daily; the cmdlet skips accounts that already have a `scheduled`
   snapshot where `date_trunc('quarter', taken_at) = date_trunc('quarter', now())` —
   self-healing, idempotent, converges to exactly one scheduled snapshot per account
   per quarter. `on_demand` / `business_review` triggers bypass the gate.
3. **Append-only in code AND grant.** The cmdlet only INSERTs (snapshot + 3 pillar rows
   per account, one transaction; a failing account rolls back alone and the fleet
   continues). Pillar rows store normalized score, weight 1 (equal-weight model), the
   covered flag, and report-ready `metrics` jsonb (m365: tenants reporting + licensed
   weight; policy: the four classification counts; darkweb: open exposures + refreshed
   tenants).
4. **Scope = mapped accounts.** The default fleet is accounts with ≥1 `account_tenant`
   row; unmapped accounts would snapshot all-uncovered F-grades forever (noise, not
   signal). `-AccountId` reaches any account explicitly.
5. **The Business Review trigger is cross-repo, not built here.** The GUI never runs
   processes (system ADR-0042): Business Review creation must call a process that
   snapshots with `trigger='business_review'` + the review's id. That belongs to the
   cloud pipeline's narrow on-demand plane (ADR-0051 §2 two-tier split) — a TS twin of
   the score math, parity-pinned like the classification CASE already is in three
   places. Tracked as cloud-pipeline + frontend issues; this cmdlet already accepts
   `-Trigger business_review -BusinessReviewId` so the on-prem half is done.

## Consequences

- Every mapped account gains one immutable scheduled snapshot per calendar quarter from
  the first nightly run of the quarter; QBR/report trend lines read history that is
  never recomputed (formula changes only affect future snapshots, per ADR-0051).
- Score Model v1 math now exists in two parity-pinned implementations (frontend TS,
  this module's PS) and will gain a third (cloud pipeline TS) for the QBR hook — same
  discipline as the posture classification CASE.
- The operator's single `Register-ImperionTask` run (held for the #81 service-identity
  bootstrap) now registers nine tasks; nothing new runs unattended before #81.

## Security impact

Reads `account_tenant` + `tenant_posture`, INSERTs the two snapshot tables — all within
the pipeline role's existing 0063 grants; immutability is enforced by the missing
UPDATE/DELETE grant, not convention. No Graph calls, no new scopes, no secrets. Snapshot
rows contain only aggregate posture numbers — no client PII.
