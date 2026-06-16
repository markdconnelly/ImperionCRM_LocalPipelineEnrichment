function Get-ImperionPolicyCatalog {
    <#
    .SYNOPSIS
        The shared map of security-posture policy types -> observed bronze table + golden-state table.
    .DESCRIPTION
        One source of truth used by Invoke-ImperionPolicySync, Set-ImperionPolicyGoldenState,
        Get-ImperionPolicyDrift, and Invoke-ImperionPostureMerge so they always agree on table
        names and keys. Observed tables all expose policy_name + external_id + content_hash;
        golden tables are keyed on (tenant_id, policy_id).

        The `Silver` flag marks families the on-prem posture SILVER merge
        (Invoke-ImperionPostureMerge) is allowed to write into posture_policy. The
        posture_policy.policy_family column carries a FRONT-END-OWNED CHECK constraint that lists
        exactly the silver-eligible families; a family not in that constraint must NOT be merged
        to silver until the front-end widens it (schema is front-end-owned, system CLAUDE.md §1).
        Bronze + golden + drift (Get-ImperionPolicyDrift) work for EVERY family regardless of the
        flag — only the silver write is gated.
    #>
    @(
        [pscustomobject]@{ Key = 'conditional-access';  Source = 'm365';     Observed = 'entra_conditional_access_policies'; Golden = 'conditional_access_policies_golden';      Silver = $true }
        [pscustomobject]@{ Key = 'intune-security';     Source = 'intune';   Observed = 'intune_security_policies';          Golden = 'intune_security_policies_golden';         Silver = $true }
        [pscustomobject]@{ Key = 'device-configuration'; Source = 'intune';  Observed = 'device_configuration_policies';      Golden = 'device_configuration_policies_golden';     Silver = $true }
        [pscustomobject]@{ Key = 'autopilot';           Source = 'intune';   Observed = 'autopilot_policies';                Golden = 'autopilot_policies_golden';               Silver = $true }
        [pscustomobject]@{ Key = 'defender-xdr';        Source = 'defender'; Observed = 'defender_xdr_security_policies';     Golden = 'defender_xdr_security_policies_golden';    Silver = $true }
        # Purview compliance — posture only (config + compliance state, NO alerts), joins the
        # existing golden-state/drift engine (issue #196, ADR-0019 §2; migration 0119). Silver = $false:
        # the posture_policy.policy_family CHECK constraint does not yet list 'purview_compliance'
        # (front-end-owned widening, proposed back as a FE issue per ADR-0019 §Operational), so it is
        # bronze+golden+drift only for now and is held out of the silver merge until the FE lands it.
        [pscustomobject]@{ Key = 'purview-compliance';  Source = 'm365';     Observed = 'purview_compliance_policies';        Golden = 'purview_compliance_golden';               Silver = $false }
    )
}
