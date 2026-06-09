function Get-ImperionPolicyCatalog {
    <#
    .SYNOPSIS
        The shared map of security-posture policy types -> observed bronze table + golden-state table.
    .DESCRIPTION
        One source of truth used by Invoke-ImperionPolicySync, Set-ImperionPolicyGoldenState,
        and Get-ImperionPolicyDrift so they always agree on table names and keys. Observed
        tables all expose policy_name + external_id + content_hash; golden tables are keyed on
        (tenant_id, policy_id).
    #>
    @(
        [pscustomobject]@{ Key = 'conditional-access';  Source = 'm365';     Observed = 'entra_conditional_access_policies'; Golden = 'conditional_access_policies_golden' }
        [pscustomobject]@{ Key = 'intune-security';     Source = 'intune';   Observed = 'intune_security_policies';          Golden = 'intune_security_policies_golden' }
        [pscustomobject]@{ Key = 'device-configuration'; Source = 'intune';  Observed = 'device_configuration_policies';      Golden = 'device_configuration_policies_golden' }
        [pscustomobject]@{ Key = 'autopilot';           Source = 'intune';   Observed = 'autopilot_policies';                Golden = 'autopilot_policies_golden' }
        [pscustomobject]@{ Key = 'defender-xdr';        Source = 'defender'; Observed = 'defender_xdr_security_policies';     Golden = 'defender_xdr_security_policies_golden' }
    )
}
