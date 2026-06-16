# Integration — Microsoft Purview compliance posture (Graph)

**Purpose.** Add Microsoft Purview **configuration + compliance state** to the security-posture
set (Secure Score / Conditional Access / Intune / Defender XDR golden-state + drift) so the
posture picture is complete (issue #196, **ADR-0019 §2**; front-end migration **0119**).

> **POSTURE ONLY — Purview ALERTS are explicitly NOT ingested** (ADR-0019 §2). This collector
> reads only compliance policy config + state.

## Pipeline — the existing golden-state/drift engine, unchanged
| What | Cmdlet | Observed bronze (FE 0119) | Golden baseline (FE 0119) | Source |
| --- | --- | --- | --- | --- |
| Purview compliance | `Invoke-ImperionPurviewComplianceSync` | `purview_compliance_policies` | `purview_compliance_golden` | `m365` |

Purview joins via the **identical `*_policies` + `*_golden` pattern** (ADR-0008/0010): it is just
another family in `Get-ImperionPolicyCatalog` (`purview-compliance`), so the **existing** engine
covers it with **no new drift mechanism**:
- `Invoke-ImperionPurviewComplianceSync` pulls observed policies (read-only Graph), flattens to
  `purview_compliance_policies` with change detection, then logs drift for the family.
- `Set-ImperionPolicyGoldenState -PolicyType purview-compliance -ApprovedBy <who>` promotes a
  current policy to the golden baseline — **human-gated**, as for every golden state.
- `Get-ImperionPolicyDrift -PolicyType purview-compliance` classifies
  **compliant / drift / ungoverned / missing** by `content_hash` comparison.

### Silver posture merge — held out for now (front-end-owned CHECK constraint)
`Invoke-ImperionPostureMerge` writes `posture_policy.policy_family`, which carries a
**front-end-owned CHECK constraint** listing the silver-eligible families. The catalog marks
Purview `Silver = $false`, so it is **bronze + golden + drift only** and is **held out of the
silver merge** until the front end widens that constraint to include `purview_compliance` (propose
it back as a front-end issue, parallel to the schema-ownership rule, ADR-0019 §Operational /
system CLAUDE.md §1). The other five families are unaffected (the merge still writes exactly them).

## Auth — read-only Graph via the per-client onboarding app (CLAUDE.md §3, pipeline ADR-0018)
`Get-ImperionGraphToken` cert-SP app-only token in the target tenant (the onboarding app, read-only;
NOT GDAP). Single-tenant by default; fan-out via `IMPERION_M365_TENANT_IDS`. **No net-new secret**
is introduced by this collector.

> **CONFIRM BEFORE LIVE USE.** The Purview compliance Graph surface
> (`-PolicyUri`, default `/beta/security/dataSecurityAndGovernance/compliancePolicies`) and the
> field names are modeled from the documented API but **UNVERIFIED** against a live consented
> tenant; an unmatched flat column lands NULL (full payload in `raw_payload`). **If a Purview pull
> turns out to need a distinct Graph scope/app**, that is a **named, human-gated grant addition**
> (CLAUDE.md §8) recorded here — never invented silently.

## Cadence, gates & DORMANT status (scheduled-tasks/README.md)
`scheduled-tasks/security/purview-compliance.task.ps1` — **daily** (compliance config is
slow-changing). Gates (fail soft — catch logs `Warn` + exits clean):
1. **Schema gate: CLEAR.** FE migration 0119 (`purview_compliance_policies` /
   `purview_compliance_golden`) is SHIPPED + prod-applied.
2. **Onboarding-app consent** for the target tenant.
3. **Task registration** deferred to server bringup (#102).
4. **CONFIRM-BEFORE-LIVE:** the Graph surface + fields (above).

**DORMANT until creds provisioned (#102) + the Graph surface confirmed live.**

## Provenance & PII posture
Posture config only (policy names, types, states, scopes) — no row-level user data. Rows stamped
`source` / `collected_at`. See also
[`../database/golden-states-and-drift.md`](../database/golden-states-and-drift.md).
