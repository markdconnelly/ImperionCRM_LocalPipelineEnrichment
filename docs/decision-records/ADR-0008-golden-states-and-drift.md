# ADR-0008 — Golden states + drift detection for security-posture policies

- **Status:** Accepted
- **Date:** 2026-06-08
- **Deciders:** Mark (human), Claude Code

## Problem & context
Beyond inventorying configuration, Mark wants an approved **golden state** (baseline) for the
key security-posture policy types, so the pipeline can detect **drift** from the approved
configuration over time: Conditional Access, Intune security, device configuration,
Autopilot, and Defender XDR security policies. Plus polling of **Microsoft Secure Score**
attributes.

## Decision
1. **Observed vs. golden, per policy type.** Each type has an **observed** bronze table
   (current state, change-detected on every sync) and a **golden** table holding the approved
   baseline keyed on `(tenant_id, policy_id)` with `golden_hash`, `golden_payload`,
   `approved_by`, `approved_at`, `notes`. Tables created by a front-end migration
   (`sql/security_posture_schema.sql`, ADR-0005).
2. **Drift = hash comparison.** `Get-ImperionPolicyDrift` full-outer-joins observed↔golden
   per type and classifies each policy: **compliant** (hashes match), **drift** (changed),
   **ungoverned** (observed, no baseline yet), **missing** (baseline exists, policy gone).
   `Invoke-ImperionPolicySync` runs the comparison after each pull and logs the summary.
3. **Promotion is a human action.** `Set-ImperionPolicyGoldenState` captures the current
   observed policy as the approved baseline (single id or `-All`), stamped with approver +
   notes. Approving a baseline is a posture decision — surface it, don't auto-baseline.
4. **Secure Score** is polled into `secure_scores` (overall snapshots) and
   `secure_score_control_profiles` (the control attributes). Read-only.
5. **Defender XDR vs. Intune-security split** is by endpoint-security **template family**
   (Antivirus / EDR / Firewall / ASR → Defender; the rest of the settings catalog → Intune
   security) — flagged as an assumption to confirm on first live pull.

## Consequences
- **Security:** turns the pipeline into a posture-drift detector feeding the agent; golden
  baselines are auditable (who approved, when). All reads are least-privilege (Policy.Read.All,
  DeviceManagementConfiguration.Read.All, DeviceManagementServiceConfig.Read.All,
  SecurityEvents.Read.All).
- **Cost:** negligible; change detection avoids needless writes.
- **Operational:** drift surfaces in logs and (later) to the front-end/agent; an operator
  promotes baselines after review.
- **Future:** alert on `drift`/`missing`; auto-open a ticket; extend golden states to other
  policy families; diff `golden_payload` vs current `raw_payload` for field-level drift.

## Cross-references
This repo `CLAUDE.md §5`; [integrations/security-posture-policies.md](../integrations/security-posture-policies.md),
[integrations/secure-score.md](../integrations/secure-score.md),
[database/golden-states-and-drift.md](../database/golden-states-and-drift.md).
