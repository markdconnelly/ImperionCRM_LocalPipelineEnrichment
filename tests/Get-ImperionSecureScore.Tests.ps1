#Requires -Modules Pester
# PARITY PIN — these vectors mirror the frontend's
# src/lib/security/imperion-score.test.ts (Score Model v1, frontend ADR-0051 §4)
# case for case. Get-ImperionSecureScore is the PowerShell twin of
# imperion-score.ts: if one changes, change both, and keep these vectors in
# lockstep with the frontend test file.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    # Mirrors the frontend test's rollup() factory: a mapped tenant with no data.
    function script:New-Rollup {
        param([hashtable] $Override = @{})
        $row = @{
            secure_score_current = $null
            secure_score_max     = $null
            licensed_user_count  = $null
            policies_compliant   = 0
            policies_drift       = 0
            policies_ungoverned  = 0
            policies_missing     = 0
            exposures_open       = 0
            refreshed_at         = $null
        }
        foreach ($k in $Override.Keys) { $row[$k] = $Override[$k] }
        [pscustomobject]$row
    }
}

Describe 'Get-ImperionSecureScore — Score Model v1 (frontend imperion-score.ts parity)' {
    It 'weights the m365 pillar by licensed users across tenants' {
        $score = Get-ImperionSecureScore -TenantPosture @(
            (New-Rollup @{ secure_score_current = 50; secure_score_max = 100; licensed_user_count = 90; refreshed_at = '2026-06-11' }),
            (New-Rollup @{ secure_score_current = 100; secure_score_max = 100; licensed_user_count = 10; refreshed_at = '2026-06-11' })
        )
        $m365 = $score.Pillars | Where-Object Pillar -EQ 'm365_secure_score'
        # (50% × 90 + 100% × 10) / 100 = 55%
        $m365.Covered | Should -BeTrue
        $m365.Score | Should -Be 55
    }

    It 'computes policy_compliance across all families and tenants' {
        $score = Get-ImperionSecureScore -TenantPosture @(
            (New-Rollup @{ policies_compliant = 6; policies_drift = 2; refreshed_at = '2026-06-11' }),
            (New-Rollup @{ policies_ungoverned = 1; policies_missing = 1; refreshed_at = '2026-06-11' })
        )
        $policy = $score.Pillars | Where-Object Pillar -EQ 'policy_compliance'
        $policy.Covered | Should -BeTrue
        $policy.Score | Should -Be 60   # 6 / 10
    }

    It 'darkweb pillar: 100 − 10 per open exposure, floored at 0' {
        $score = Get-ImperionSecureScore -TenantPosture @(
            (New-Rollup @{ exposures_open = 3; refreshed_at = '2026-06-11' })
        )
        ($score.Pillars | Where-Object Pillar -EQ 'darkweb').Score | Should -Be 70

        $floored = Get-ImperionSecureScore -TenantPosture @(
            (New-Rollup @{ exposures_open = 15; refreshed_at = '2026-06-11' })
        )
        ($floored.Pillars | Where-Object Pillar -EQ 'darkweb').Score | Should -Be 0
    }

    It 'no coverage scores 0 and never reads as fine — an unrefreshed account is not a perfect 100' {
        $score = Get-ImperionSecureScore -TenantPosture @((New-Rollup)) # mapped, never classified
        $score.Pillars | ForEach-Object {
            $_.Covered | Should -BeFalse
            $_.Score | Should -Be 0
        }
        $score.Composite | Should -Be 0
        $score.Grade | Should -Be 'F'
    }

    It 'composite is the equal-weight mean over ALL pillars (uncovered contribute 0)' {
        $score = Get-ImperionSecureScore -TenantPosture @(
            (New-Rollup @{ secure_score_current = 90; secure_score_max = 100; licensed_user_count = 10; refreshed_at = '2026-06-11' })
        ) # m365 = 90, darkweb = 100, policy uncovered = 0
        $score.Composite | Should -Be ([math]::Round((90 + 0 + 100) / 3 * 10) / 10)
    }

    It 'rounds the stored composite to one decimal, half away from zero (JS Math.round parity)' {
        # Only darkweb covered → composite = darkweb/3; 100/3 = 33.333… stores 33.3,
        # 70/3 = 23.333… stores 23.3. Pins the rounding mode through the public surface.
        foreach ($case in @(
                @{ exposures = 0; composite = 33.3 },
                @{ exposures = 3; composite = 23.3 },
                @{ exposures = 15; composite = 0 })) {
            $score = Get-ImperionSecureScore -TenantPosture @(
                (New-Rollup @{ exposures_open = $case.exposures; refreshed_at = '2026-06-11' })
            )
            $score.Composite | Should -Be $case.composite
        }
    }

    It 'grade bands: A ≥ 90, B ≥ 80, C ≥ 70, D ≥ 60, else F' {
        # Drive the bands through the public surface: a single fully-reporting tenant
        # with current/max = b/100 on every covered pillar pins each band edge.
        foreach ($case in @(
                @{ score = 90; exposures = 1; compliant = 90; drift = 10; grade = 'A' },   # 90/90/90
                @{ score = 80; exposures = 2; compliant = 80; drift = 20; grade = 'B' },   # 80/80/80
                @{ score = 70; exposures = 3; compliant = 70; drift = 30; grade = 'C' },   # 70/70/70
                @{ score = 60; exposures = 4; compliant = 60; drift = 40; grade = 'D' },   # 60/60/60
                @{ score = 59; exposures = 5; compliant = 59; drift = 41; grade = 'F' })) { # 59/50/59
            $score = Get-ImperionSecureScore -TenantPosture @(
                (New-Rollup @{
                        secure_score_current = $case.score; secure_score_max = 100
                        licensed_user_count = 10; exposures_open = $case.exposures
                        policies_compliant = $case.compliant; policies_drift = $case.drift
                        refreshed_at = '2026-06-11'
                    })
            )
            $score.Grade | Should -Be $case.grade
        }
    }

    It 'an empty rollup set (no mapped tenants) is all-uncovered F' {
        $score = Get-ImperionSecureScore -TenantPosture @()
        $score.Composite | Should -Be 0
        $score.Grade | Should -Be 'F'
        @($score.Pillars).Count | Should -Be 3
    }

    It 'stamps ModelVersion 1 and equal pillar weights' {
        $score = Get-ImperionSecureScore -TenantPosture @((New-Rollup))
        $score.ModelVersion | Should -Be 1
        $score.Pillars | ForEach-Object { $_.Weight | Should -Be 1 }
        ($score.Pillars.Pillar | Sort-Object) | Should -Be @('darkweb', 'm365_secure_score', 'policy_compliance')
    }
}
