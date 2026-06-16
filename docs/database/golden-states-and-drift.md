# Golden states & drift

Security-posture policies are tracked as **observed** (current) vs. **golden** (approved
baseline). Drift is a hash comparison (ADR-0008). Schema:
`sql/security_posture_schema.sql` (front-end-owned, ADR-0005).

## Tables
- **Observed (bronze):** `entra_conditional_access_policies`, `intune_security_policies`,
  `device_configuration_policies`, `autopilot_policies`, `defender_xdr_security_policies`,
  **`purview_compliance_policies`** (Purview compliance posture, ADR-0019 §2; refreshed by
  `Invoke-ImperionPurviewComplianceSync`) — each exposes `policy_name`, `external_id`,
  `content_hash` plus the standard envelope, refreshed (change-detected) on every sync.
- **Golden:** `*_golden`, keyed `(tenant_id, policy_id)`:
  `golden_hash`, `golden_payload (jsonb)`, `approved_by`, `approved_at`, `notes` —
  including **`purview_compliance_golden`**.

## Drift classification
`Get-ImperionPolicyDrift` full-outer-joins observed↔golden per type:

| Status | Meaning |
| --- | --- |
| `compliant` | observed `content_hash` == golden `golden_hash` |
| `drift` | observed differs from the approved baseline |
| `ungoverned` | observed exists, no golden baseline approved yet |
| `missing` | golden baseline exists but the policy is gone from the tenant |

```sql
SELECT COALESCE(o.external_id, g.policy_id) AS policy_id,
       CASE WHEN g.policy_id IS NULL THEN 'ungoverned'
            WHEN o.external_id IS NULL THEN 'missing'
            WHEN o.content_hash = g.golden_hash THEN 'compliant'
            ELSE 'drift' END AS status
FROM entra_conditional_access_policies o
FULL OUTER JOIN conditional_access_policies_golden g
  ON g.tenant_id = o.tenant_id AND g.policy_id = o.external_id
WHERE COALESCE(o.tenant_id, g.tenant_id) = :tenant;
```

## Promotion (baseline approval)
`Set-ImperionPolicyGoldenState` copies the current observed policy (`content_hash` +
`raw_payload`) into the golden table with approver + timestamp + notes. A baseline approval
is a **human posture decision** (gated). After promotion the policy reads `compliant` until
its configuration changes.

## Drift → agent
Once vectorized/surfaced, drift and ungoverned/missing policies become part of the company
knowledge the front-end agent is aware of — "what changed against approved baseline" is a
first-class question the agent can answer.

## Silver (canonical) — posture_policy + tenant_posture

Since ADR-0010 the classification is no longer only an ad-hoc read: the nightly
`Invoke-ImperionPostureMerge` (`Imperion-PostureMerge`, 03:20) replaces every tenant's
`posture_policy` rows with this same FULL OUTER JOIN classification and rolls up
`tenant_posture` (latest Secure Score, classification counts, open exposures via
`account_tenant`). The cloud pipeline's `POST /api/refresh {source:'posture', accountId}`
(cloud pipeline ADR-0015) is the narrow on-demand twin. The CASE is a pinned parity
contract across `Get-ImperionPolicyDrift`, this merge, and the cloud runner — change one,
change all three (Pester pins it here).

**Purview is bronze+golden+drift only — held out of the silver merge (ADR-0019 §2).** The
`posture_policy.policy_family` column carries a **front-end-owned CHECK constraint** that lists
the silver-eligible families; it does not yet include `purview_compliance`. So
`Get-ImperionPolicyCatalog` marks the Purview entry `Silver = $false`, and
`Invoke-ImperionPostureMerge` filters to `Silver`-flagged families — Purview drift works (via
`Get-ImperionPolicyDrift` / `Invoke-ImperionPurviewComplianceSync`) but is **not** written into
`posture_policy` until the front end widens the CHECK constraint (propose it back as a front-end
issue, system CLAUDE.md §1). The other five families merge to silver exactly as before.
