function Get-ImperionPolicyDrift {
    <#
    .SYNOPSIS
        Compare observed security-posture policies to their golden states and report compliance/drift.
    .DESCRIPTION
        For each policy type (or one via -PolicyType), full-outer-joins the observed bronze
        table to its golden-state table and classifies every policy:
          compliant  — observed hash matches the approved golden hash
          drift      — observed differs from golden (configuration changed)
          ungoverned — observed but no golden baseline approved yet
          missing    — golden baseline exists but the policy is gone from the tenant
        Returns the rows; callers can log or surface them. Pass -Connection to reuse an open
        connection; otherwise one is opened and disposed. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to evaluate; defaults to the partner tenant.
    .PARAMETER PolicyType
        Optional single type key (e.g. 'conditional-access'); default evaluates all.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse.
    .EXAMPLE
        Get-ImperionPolicyDrift | Where-Object status -eq 'drift'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string] $TenantId,
        [ValidateSet('conditional-access', 'intune-security', 'device-configuration', 'autopilot', 'defender-xdr')]
        [string] $PolicyType,
        $Connection
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        $catalog = Get-ImperionPolicyCatalog
        if ($PolicyType) { $catalog = $catalog | Where-Object Key -eq $PolicyType }

        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($p in $catalog) {
            $sql = @"
SELECT
    COALESCE(o.external_id, g.policy_id)     AS policy_id,
    COALESCE(o.policy_name, g.policy_name)   AS policy_name,
    o.content_hash                           AS current_hash,
    g.golden_hash                            AS golden_hash,
    CASE
        WHEN g.policy_id   IS NULL THEN 'ungoverned'
        WHEN o.external_id IS NULL THEN 'missing'
        WHEN o.content_hash = g.golden_hash THEN 'compliant'
        ELSE 'drift'
    END AS status
FROM "$($p.Observed)" o
FULL OUTER JOIN "$($p.Golden)" g
    ON g.tenant_id = o.tenant_id AND g.policy_id = o.external_id
WHERE COALESCE(o.tenant_id, g.tenant_id) = @t
"@
            $rows = Invoke-ImperionDbQuery -Connection $Connection -Sql $sql -Parameters @{ t = $TenantId }
            foreach ($r in $rows) {
                $results.Add([pscustomobject]@{
                    policy_type  = $p.Key
                    policy_id    = $r.policy_id
                    policy_name  = $r.policy_name
                    status       = $r.status
                    current_hash = $r.current_hash
                    golden_hash  = $r.golden_hash
                })
            }
        }
        return $results.ToArray()
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
