# Integration — security-posture policies (+ golden states)

**Purpose.** Pull the current state of the key security-posture policy types, land them in
observed bronze tables, and compare each to its **golden state** to detect drift (ADR-0008).
Cmdlets: `Invoke-ImperionPolicySync`, `Get-ImperionPolicyDrift`, `Set-ImperionPolicyGoldenState`.

## Auth (read-only, pipeline ADR-0018)
Cert app-only Graph token. Permissions: `Policy.Read.All` (Conditional Access),
`DeviceManagementConfiguration.Read.All` (Intune security / device config / endpoint
security), `DeviceManagementServiceConfig.Read.All` (Autopilot). Per-client security posture (ADR-0126):
`Invoke-ImperionPolicySync` fans out across **every mapped client tenant** via
`Invoke-ImperionM365EstateSweep` — the registry-driven (`account_tenant ⨝` an active `m365`
`connection`), per-tenant fail-isolated sweep the directory collectors use (#358/#266; #379).
`IMPERION_M365_TENANT_IDS` pins a subset, `-TenantId` pins one; an empty registry is dormant-safe
(partner tenant once). Each client tenant is reached via the per-client onboarding app (§3); a
tenant with no consent/credential is skipped (Warn), never blocking the rest.

## Policy types, endpoints, tables
| Type | Graph endpoint | Observed table | Golden table |
| --- | --- | --- | --- |
| Conditional Access | `v1.0/identity/conditionalAccess/policies` | `entra_conditional_access_policies` | `conditional_access_policies_golden` |
| Intune security | `beta/deviceManagement/configurationPolicies` (non-Defender families) | `intune_security_policies` | `intune_security_policies_golden` |
| Device configuration | `v1.0/deviceManagement/deviceConfigurations` | `device_configuration_policies` | `device_configuration_policies_golden` |
| Autopilot | `v1.0/deviceManagement/windowsAutopilotDeploymentProfiles` | `autopilot_policies` | `autopilot_policies_golden` |
| Defender XDR | `beta/deviceManagement/configurationPolicies` (endpoint-security families) | `defender_xdr_security_policies` | `defender_xdr_security_policies_golden` |

**Defender vs. Intune split:** `configurationPolicies` is partitioned by
`templateReference.templateFamily`. Families `endpointSecurityAntivirus`,
`endpointSecurityEndpointDetectionAndResponse`, `endpointSecurityFirewall`,
`endpointSecurityAttackSurfaceReductionRules` → **Defender XDR**; everything else → **Intune
security**. *(Assumption — confirm the family set on first live pull.)*

## Drift model
Observed tables expose `policy_name`, `external_id`, `content_hash`. Golden tables hold the
approved baseline keyed `(tenant_id, policy_id)` with `golden_hash`. `Get-ImperionPolicyDrift`
classifies each policy: **compliant / drift / ungoverned / missing**
([../database/golden-states-and-drift.md](../database/golden-states-and-drift.md)).

## Promoting a baseline (human-gated)
```powershell
Initialize-ImperionContext
Set-ImperionPolicyGoldenState -PolicyType conditional-access -PolicyId <id> -ApprovedBy 'mark' -Notes 'baseline 2026-06'
# or baseline every current policy of a type:
Set-ImperionPolicyGoldenState -PolicyType conditional-access -All -ApprovedBy 'mark'
```

## Assumptions to confirm
- `configurationPolicies` is a **beta** endpoint; pin the api/base if it graduates.
- Endpoint-security template-family names per the tenant's Intune version.
- Whether older `deviceManagement/intents` (template-based endpoint security) should also be
  pulled alongside `configurationPolicies`.
