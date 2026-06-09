#Requires -Modules Pester
# Hermetic test for Set-ImperionPolicyGoldenState: DB write mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionPolicyGoldenState' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbNonQuery { 1 }
        }
    }

    It 'targets a single policy with an external_id filter and the id parameter' {
        InModuleScope ImperionPipeline {
            Set-ImperionPolicyGoldenState -PolicyType 'conditional-access' -PolicyId 'p1' -ApprovedBy 'mark' | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Sql -match 'AND external_id = @id' -and $Parameters.id -eq 'p1' -and $Parameters.by -eq 'mark'
            }
        }
    }

    It 'baselines every policy of the type with -All (no external_id filter, no id param)' {
        InModuleScope ImperionPipeline {
            Set-ImperionPolicyGoldenState -PolicyType 'autopilot' -All -ApprovedBy 'mark' | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Sql -notmatch 'AND external_id' -and -not $Parameters.ContainsKey('id')
            }
        }
    }

    It 'does not write when -WhatIf is supplied (ShouldProcess)' {
        InModuleScope ImperionPipeline {
            Set-ImperionPolicyGoldenState -PolicyType 'autopilot' -All -ApprovedBy 'mark' -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'returns the affected row count' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbNonQuery { 7 }
            $n = Set-ImperionPolicyGoldenState -PolicyType 'autopilot' -All -ApprovedBy 'mark'
            $n | Should -Be 7
        }
    }
}
