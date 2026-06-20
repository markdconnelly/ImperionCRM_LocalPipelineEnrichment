function Get-ImperionKnowledgePosture {
    <#
    .SYNOPSIS
        Compose one gold knowledge-object row per tenant summarizing its security posture.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009) over the posture
        bronze set (migration 0038 / ADR-0008): the latest Secure Score snapshot per tenant
        plus every observed policy type (Conditional Access, Intune security, device
        configuration, Autopilot, Defender XDR) classified against its golden baseline by
        reusing Get-ImperionPolicyDrift (compliant / drift / ungoverned / missing). One
        knowledge object per tenant: score, per-type policy counts by drift status, and the
        notable gaps (every non-compliant policy, named).

        Unlike the CRM composers, the tenant axis is the data itself: with no -TenantId the
        composer enumerates every tenant observed across the posture tables and stamps each
        row with ITS tenant (per-tenant isolation, CLAUDE.md §3) — the spine's
        -PerRowTenant mode.

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): tenant enumeration is the primary query, the latest-score lookup is a
        related query, and the drift classification runs per tenant in the compose block
        via the spine's $context.Connection.
        Output rows are flat PSCustomObjects in the knowledge_object shape
        (entity_type='posture', entity_ref = the tenant id). Read-only;
        pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Restrict to one tenant. Default: every tenant observed in the posture tables.
    .PARAMETER NotableGapLimit
        How many non-compliant policies to name in the body. Default 25.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgePosture | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId,
        [ValidateRange(0, 200)][int] $NotableGapLimit = 25
    )

    # Captured under names the spine's parameters cannot shadow when the scriptblocks
    # resolve variables dynamically through the spine's scope (and so the analyzer sees
    # the parameters consumed outside the scriptblocks).
    $requestedTenantId = $TenantId
    $gapLimit = $NotableGapLimit

    $postureTenantQuery = {
        param($activeConnection)
        $tenantRows = Invoke-ImperionDbQuery -Connection $activeConnection -Sql @'
SELECT DISTINCT tenant_id FROM (
          SELECT tenant_id FROM secure_scores
    UNION SELECT tenant_id FROM entra_conditional_access_policies
    UNION SELECT tenant_id FROM intune_security_policies
    UNION SELECT tenant_id FROM device_configuration_policies
    UNION SELECT tenant_id FROM autopilot_policies
    UNION SELECT tenant_id FROM defender_xdr_security_policies
) posture_tenants
 ORDER BY tenant_id
'@
        if ($requestedTenantId) { $tenantRows = @($tenantRows | Where-Object { $_.tenant_id -eq $requestedTenantId }) }
        $tenantRows
    }

    # Latest Secure Score snapshot per tenant (created_date_time is ISO-8601 text — sorts).
    $relatedQueries = @{
        scores = @{ KeyColumn = 'tenant_id'; Sql = @'
SELECT DISTINCT ON (tenant_id) tenant_id, current_score, max_score, created_date_time
  FROM secure_scores
 ORDER BY tenant_id, created_date_time DESC
'@ }
    }

    Invoke-ImperionKnowledgeCompose -EntityType 'posture' -Connection $Connection -PerRowTenant `
        -LogLabel 'posture' -CountName 'tenants' `
        -EmptyMessage 'knowledge posture: no posture bronze found for any tenant.' `
        -Query $postureTenantQuery -RelatedQueries $relatedQueries `
        -Compose {
        param($tenantRow, $related, $composeContext)
        $tenant = $tenantRow.tenant_id
        $driftRows = @(Get-ImperionPolicyDrift -TenantId $tenant -Connection $composeContext.Connection)

        $lines = [System.Collections.Generic.List[string]]::new()
        $title = "Security posture: tenant $tenant"
        $lines.Add($title)

        $score = if ($related['scores'].ContainsKey($tenant)) { $related['scores'][$tenant][0] } else { $null }
        if ($score) {
            $currentScore = 0.0
            $maxScore = 0.0
            $scoreLine = "Secure Score: $($score.current_score) of $($score.max_score)"
            if ([double]::TryParse([string]$score.current_score, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$currentScore) -and
                [double]::TryParse([string]$score.max_score, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$maxScore) -and
                $maxScore -gt 0) {
                $scoreLine += " ($([math]::Round(($currentScore / $maxScore) * 100, 1))%)"
            }
            if ($score.created_date_time) { $scoreLine += " — snapshot $($score.created_date_time)" }
            $lines.Add($scoreLine)
        }
        else {
            $lines.Add('Secure Score: no snapshot collected yet.')
        }

        $statusTotals = [ordered]@{ compliant = 0; drift = 0; ungoverned = 0; missing = 0 }
        if (@($driftRows).Count -gt 0) {
            $lines.Add('')
            $lines.Add('Policy posture by type (observed vs approved golden baseline):')
            foreach ($typeGroup in ($driftRows | Group-Object policy_type | Sort-Object Name)) {
                $byStatus = @{}
                foreach ($statusGroup in ($typeGroup.Group | Group-Object status)) { $byStatus[$statusGroup.Name] = $statusGroup.Count }
                foreach ($statusKey in @($statusTotals.Keys)) {
                    if ($byStatus.ContainsKey($statusKey)) { $statusTotals[$statusKey] += $byStatus[$statusKey] }
                }
                $counts = foreach ($statusKey in 'compliant', 'drift', 'ungoverned', 'missing') {
                    if ($byStatus.ContainsKey($statusKey)) { "$statusKey $($byStatus[$statusKey])" }
                }
                $lines.Add("- $($typeGroup.Name): $($typeGroup.Count) policies — $($counts -join ' · ')")
            }

            $gaps = @($driftRows | Where-Object { $_.status -ne 'compliant' })
            if (@($gaps).Count -gt 0) {
                $lines.Add('')
                $lines.Add("Notable gaps ($(@($gaps).Count) policies not compliant with baseline):")
                $explanations = @{
                    drift      = 'configuration differs from the approved baseline'
                    ungoverned = 'no approved baseline yet'
                    missing    = 'baseline approved but policy gone from the tenant'
                }
                foreach ($gap in (@($gaps) | Select-Object -First $gapLimit)) {
                    $gapName = if ($gap.policy_name) { $gap.policy_name } else { $gap.policy_id }
                    $lines.Add("- [$($gap.policy_type)] $gapName — $($gap.status) ($($explanations[$gap.status]))")
                }
                if (@($gaps).Count -gt $gapLimit) {
                    $lines.Add("- … and $(@($gaps).Count - $gapLimit) more.")
                }
            }
        }
        else {
            $lines.Add('')
            $lines.Add('No security-posture policies observed for this tenant yet.')
        }

        [pscustomobject]@{
            tenant_id  = $tenant
            entity_ref = $tenant
            title      = $title
            body       = ($lines -join "`n").Trim()
            source     = 'local-pipeline'
            metadata   = @{
                secure_score = $(if ($score) { $score.current_score } else { $null })
                secure_score_max = $(if ($score) { $score.max_score } else { $null })
                policies = @($driftRows).Count
                compliant = $statusTotals['compliant']; drift = $statusTotals['drift']
                ungoverned = $statusTotals['ungoverned']; missing = $statusTotals['missing']
            }
        }
    }
}
