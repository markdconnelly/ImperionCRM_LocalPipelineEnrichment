#Requires -Modules Pester
# Hermetic test for Set-ImperionDnsGoldenState (issue #157): DB write mocked in module scope.
# Mirrors Set-ImperionPolicyGoldenState - human-gated per-domain baseline approval.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionDnsGoldenState' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 't1' } }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbNonQuery { 1 }
        }
    }

    It 'baselines a single domain with a domain filter and the domain parameter' {
        InModuleScope ImperionPipeline {
            Set-ImperionDnsGoldenState -Domain 'contoso.com' -ApprovedBy 'mark' | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Sql -match 'AND r\.domain = @domain' -and
                $Parameters.domain -eq 'contoso.com' -and
                $Parameters.by -eq 'mark'
            }
        }
    }

    It 'baselines every domain with -All (no domain filter, no domain param)' {
        InModuleScope ImperionPipeline {
            Set-ImperionDnsGoldenState -All -ApprovedBy 'mark' | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Sql -notmatch 'AND r\.domain' -and -not $Parameters.ContainsKey('domain')
            }
        }
    }

    It 'freezes the public plane by default and carries the record-stamped account_id' {
        InModuleScope ImperionPipeline {
            Set-ImperionDnsGoldenState -All -ApprovedBy 'mark' | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Parameters.plane -eq 'public' -and
                $Sql -match 'COALESCE\(max\(r\.account_id\), max\(ad\.account_id\)\)' -and
                $Sql -match 'INSERT INTO dns_golden' -and
                $Sql -match 'ON CONFLICT \(tenant_id, domain\) DO UPDATE'
            }
        }
    }

    It 'can freeze the azure plane when asked' {
        InModuleScope ImperionPipeline {
            Set-ImperionDnsGoldenState -Domain 'contoso.com' -Plane 'azure' -ApprovedBy 'mark' | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter { $Parameters.plane -eq 'azure' }
        }
    }

    It 'does not write when -WhatIf is supplied (ShouldProcess - it is a human posture decision)' {
        InModuleScope ImperionPipeline {
            Set-ImperionDnsGoldenState -All -ApprovedBy 'mark' -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'returns the affected domain count' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbNonQuery { 4 }
            $n = Set-ImperionDnsGoldenState -All -ApprovedBy 'mark'
            $n | Should -Be 4
        }
    }
}
