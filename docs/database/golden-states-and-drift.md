# Golden states & drift

Security-posture policies are tracked as **observed** (current) vs. **golden** (approved
baseline). Drift is a hash comparison (ADR-0008). Schema:
`sql/security_posture_schema.sql` (front-end-owned, ADR-0005).

## Tables
- **Observed (bronze):** `entra_conditional_access_policies`, `intune_security_policies`,
  `device_configuration_policies`, `autopilot_policies`, `defender_xdr_security_policies` —
  each exposes `policy_name`, `external_id`, `content_hash` plus the standard envelope,
  refreshed (change-detected) on every `Invoke-ImperionPolicySync`.
- **Golden:** `*_golden`, keyed `(tenant_id, policy_id)`:
  `golden_hash`, `golden_payload (jsonb)`, `approved_by`, `approved_at`, `notes`.

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
