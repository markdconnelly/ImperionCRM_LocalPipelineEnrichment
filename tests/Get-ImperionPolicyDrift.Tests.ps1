#Requires -Modules Pester
# Hermetic test for Get-ImperionPolicyDrift: the DB query is mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPolicyDrift' {
    It 'classifies one policy type and stamps policy_type on each row' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{ policy_id = 'p1'; policy_name = 'CA1'; current_hash = 'h'; golden_hash = 'h'; status = 'compliant' },
                    [pscustomobject]@{ policy_id = 'p2'; policy_name = 'CA2'; current_hash = 'h2'; golden_hash = 'h3'; status = 'drift' }
                )
            }
            $result = Get-ImperionPolicyDrift -PolicyType 'conditional-access' -Connection ([pscustomobject]@{})
            $result.Count | Should -Be 2
            ($result.policy_type | Sort-Object -Unique) | Should -Be 'conditional-access'
            ($result | Where-Object status -eq 'drift').policy_id | Should -Be 'p2'
            Should -Invoke Invoke-ImperionDbQuery -Times 1
        }
    }

    It 'evaluates all five policy types when none is specified' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Invoke-ImperionDbQuery { @() }
            Get-ImperionPolicyDrift -Connection ([pscustomobject]@{}) | Out-Null
            Should -Invoke Invoke-ImperionDbQuery -Times 5
        }
    }

    It 'passes the tenant id as a parameter (no inline interpolation)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Invoke-ImperionDbQuery { @() }
            Get-ImperionPolicyDrift -PolicyType 'autopilot' -Connection ([pscustomobject]@{}) | Out-Null
            Should -Invoke Invoke-ImperionDbQuery -Times 1 -ParameterFilter { $Parameters.t -eq 'partner' }
        }
    }
}
