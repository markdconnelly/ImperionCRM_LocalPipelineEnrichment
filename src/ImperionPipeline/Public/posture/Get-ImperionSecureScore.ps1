function Get-ImperionSecureScore {
    <#
    .SYNOPSIS
        Compute the Imperion Secure Score (Score Model v1) from an account's tenant_posture rollups.
    .DESCRIPTION
        Pure function — no DB, no Graph, no context required. PARITY CONTRACT: this is
        the PowerShell twin of the frontend's src/lib/security/imperion-score.ts
        (frontend ADR-0051 §4, Score Model v1); the Pester tests pin this math with the
        same vectors as the frontend's imperion-score.test.ts. If one changes, change
        both.

        Model v1 pillars (equal weight 1): m365_secure_score · policy_compliance ·
        darkweb. A pillar with no data is covered=false and scores 0 — no coverage is
        not "fine". The composite is the equal-weight mean over ALL model pillars
        (uncovered pillars contribute 0), rounded to one decimal half-away-from-zero
        (the frontend's Math.round); the grade is banded from the UNROUNDED composite,
        exactly as the frontend does.
    .PARAMETER TenantPosture
        The account's rollup rows — the LEFT JOIN of account_tenant onto tenant_posture
        (a mapped-but-never-merged tenant arrives as a row of NULLs, matching the
        frontend read model). Expected fields per row: secure_score_current,
        secure_score_max, licensed_user_count, policies_compliant, policies_drift,
        policies_ungoverned, policies_missing, exposures_open, refreshed_at.
    .EXAMPLE
        Get-ImperionSecureScore -TenantPosture $rollupRows
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()][AllowNull()]
        [psobject[]] $TenantPosture = @()
    )

    $rollups = @($TenantPosture)

    # m365_secure_score: licensed-user-weighted mean of current/max × 100 across
    # tenants that report a score. A tenant without a licensed-user count weighs 1
    # (still counted, never silently dropped).
    $weighted = 0.0
    $weightSum = 0.0
    $tenantsReporting = 0
    foreach ($tenant in $rollups) {
        if ($null -eq $tenant.secure_score_current -or $null -eq $tenant.secure_score_max -or
            [double]$tenant.secure_score_max -le 0) { continue }
        $weight = if ($null -ne $tenant.licensed_user_count) { [double]$tenant.licensed_user_count } else { 1.0 }
        $weighted += ([double]$tenant.secure_score_current / [double]$tenant.secure_score_max) * 100 * $weight
        $weightSum += $weight
        $tenantsReporting++
    }
    $m365 = [pscustomobject]@{
        Pillar  = 'm365_secure_score'
        Covered = $weightSum -gt 0
        Score   = if ($weightSum -gt 0) { $weighted / $weightSum } else { 0.0 }
        Weight  = 1
        Metrics = @{ tenants_reporting = $tenantsReporting; licensed_user_weight = $weightSum }
    }

    # policy_compliance: compliant / all classified, across all families + tenants.
    $compliant = 0; $drift = 0; $ungoverned = 0; $missing = 0
    foreach ($tenant in $rollups) {
        $compliant  += [int]($tenant.policies_compliant  ?? 0)
        $drift      += [int]($tenant.policies_drift      ?? 0)
        $ungoverned += [int]($tenant.policies_ungoverned ?? 0)
        $missing    += [int]($tenant.policies_missing    ?? 0)
    }
    $classified = $compliant + $drift + $ungoverned + $missing
    $policy = [pscustomobject]@{
        Pillar  = 'policy_compliance'
        Covered = $classified -gt 0
        Score   = if ($classified -gt 0) { ($compliant / $classified) * 100 } else { 0.0 }
        Weight  = 1
        Metrics = @{ compliant = $compliant; drift = $drift; ungoverned = $ungoverned; missing = $missing }
    }

    # darkweb: max(0, 100 − 10 × open exposures). Covered only once at least one
    # tenant has a computed rollup (refreshed_at) — exposures default 0, so an
    # unrefreshed account must read "No coverage", never a perfect 100.
    $refreshed = [bool]($rollups | Where-Object { $null -ne $_.refreshed_at } | Select-Object -First 1)
    $exposures = 0
    foreach ($tenant in $rollups) { $exposures += [int]($tenant.exposures_open ?? 0) }
    $darkweb = [pscustomobject]@{
        Pillar  = 'darkweb'
        Covered = $refreshed
        Score   = if ($refreshed) { [math]::Max(0, 100 - 10 * $exposures) } else { 0.0 }
        Weight  = 1
        Metrics = @{ exposures_open = $exposures; tenants_refreshed = @($rollups | Where-Object { $null -ne $_.refreshed_at }).Count }
    }

    $pillars = @($m365, $policy, $darkweb)
    $composite = ($pillars | Measure-Object -Property Score -Sum).Sum / $pillars.Count
    $grade = if ($composite -ge 90) { 'A' }
        elseif ($composite -ge 80) { 'B' }
        elseif ($composite -ge 70) { 'C' }
        elseif ($composite -ge 60) { 'D' }
        else { 'F' }

    [pscustomobject]@{
        ModelVersion = 1
        # Stored rounded; graded unrounded — both verbatim from imperion-score.ts.
        Composite    = [math]::Round($composite * 10, [System.MidpointRounding]::AwayFromZero) / 10
        Grade        = $grade
        Pillars      = $pillars
    }
}
