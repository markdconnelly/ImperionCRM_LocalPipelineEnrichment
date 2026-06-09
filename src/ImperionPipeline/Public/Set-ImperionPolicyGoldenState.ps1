function Set-ImperionPolicyGoldenState {
    <#
    .SYNOPSIS
        Promote the current observed state of a security-posture policy to its approved golden state.
    .DESCRIPTION
        Captures the current observed policy (its content hash + raw payload) into the golden
        table as the approved baseline, stamped with approver + timestamp + notes. After this,
        Get-ImperionPolicyDrift reports the policy as 'compliant' until its configuration
        changes. Promote a single policy by id, or all policies of a type with -All. This is a
        human-approval action — surface it before running broadly. Requires Initialize-ImperionContext.
    .PARAMETER PolicyType
        Which policy type's golden state to set.
    .PARAMETER PolicyId
        The observed policy's id (external_id). Omit and use -All to baseline every policy of the type.
    .PARAMETER All
        Promote every currently observed policy of the type.
    .PARAMETER ApprovedBy
        Who approved this baseline (recorded for audit).
    .PARAMETER Notes
        Optional approval notes.
    .PARAMETER TenantId
        Tenant; defaults to the partner tenant.
    .EXAMPLE
        Set-ImperionPolicyGoldenState -PolicyType conditional-access -PolicyId $id -ApprovedBy 'mark' -Notes 'baseline 2026-06'
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Single')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('conditional-access', 'intune-security', 'device-configuration', 'autopilot', 'defender-xdr')]
        [string] $PolicyType,
        [Parameter(Mandatory, ParameterSetName = 'Single')][string] $PolicyId,
        [Parameter(Mandatory, ParameterSetName = 'All')][switch] $All,
        [Parameter(Mandatory)][string] $ApprovedBy,
        [string] $Notes,
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $p = Get-ImperionPolicyCatalog | Where-Object Key -eq $PolicyType
    $target = if ($All) { "all $($p.Observed) policies" } else { "$PolicyType/$PolicyId" }

    $sql = @"
INSERT INTO "$($p.Golden)" (tenant_id, policy_id, policy_name, golden_hash, golden_payload, approved_by, approved_at, notes)
SELECT tenant_id, external_id, policy_name, content_hash, raw_payload, @by, now()::text, @notes
FROM "$($p.Observed)"
WHERE tenant_id = @t $(if (-not $All) { 'AND external_id = @id' })
ON CONFLICT (tenant_id, policy_id) DO UPDATE SET
    policy_name    = EXCLUDED.policy_name,
    golden_hash    = EXCLUDED.golden_hash,
    golden_payload = EXCLUDED.golden_payload,
    approved_by    = EXCLUDED.approved_by,
    approved_at    = EXCLUDED.approved_at,
    notes          = EXCLUDED.notes
"@
    $params = @{ by = $ApprovedBy; notes = $Notes; t = $TenantId }
    if (-not $All) { $params.id = $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Set golden state')) {
        $conn = New-ImperionDbConnection
        try {
            $affected = Invoke-ImperionDbNonQuery -Connection $conn -Sql $sql -Parameters $params
            Write-ImperionLog -Level Metric -Source 'policy' -Message "Golden state set for $target." -Data @{ policy_type = $PolicyType; approved_by = $ApprovedBy; rows = $affected }
            return $affected
        }
        finally { $conn.Dispose() }
    }
}
