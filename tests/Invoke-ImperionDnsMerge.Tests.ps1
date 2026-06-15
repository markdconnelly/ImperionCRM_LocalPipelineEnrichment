#Requires -Modules Pester
# Hermetic test for Invoke-ImperionDnsMerge (issue #157): Get-ImperionDnsDrift + the DB
# write are mocked in module scope. Asserts the idempotent per-domain upsert, account-keyed
# tenant_id, and the one-bad-domain-never-blocks-the-fleet discipline.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDnsMerge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbNonQuery { 1 }
            Mock Get-ImperionDnsDrift {
                @(
                    [pscustomobject]@{ domain = 'contoso.com'; account_id = 'acc-1'; verdict = 'managed'
                        records_compliant = 6; records_drift = 0; records_ungoverned = 0; records_missing = 0
                        score = 100; last_captured_at = '2026-06-14T00:00:00Z' }
                    [pscustomobject]@{ domain = 'fabrikam.com'; account_id = 'acc-2'; verdict = 'in-azure-readonly'
                        records_compliant = 3; records_drift = 2; records_ungoverned = 1; records_missing = 0
                        score = 50; last_captured_at = '2026-06-14T00:00:00Z' }
                )
            }
        }
    }

    It 'upserts one dns_domain row per governed domain (idempotent, keyed tenant_id+domain)' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionDnsMerge | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 2 -ParameterFilter {
                $Sql -match 'INSERT INTO dns_domain' -and
                $Sql -match 'ON CONFLICT \(tenant_id, domain\) DO UPDATE'
            }
        }
    }

    It 'keys tenant_id on the account id (account is the isolation owner) and carries account_id' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionDnsMerge | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Parameters.domain -eq 'contoso.com' -and
                $Parameters.tenant -eq 'acc-1' -and
                $Parameters.account -eq 'acc-1' -and
                $Parameters.verdict -eq 'managed'
            }
        }
    }

    It 'falls back to the domain as tenant_id when no account is mapped' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionDnsDrift {
                @([pscustomobject]@{ domain = 'orphan.com'; account_id = $null; verdict = 'not-in-azure'
                    records_compliant = 0; records_drift = 0; records_ungoverned = 0; records_missing = 0
                    score = $null; last_captured_at = $null })
            }
            Invoke-ImperionDnsMerge | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Parameters.tenant -eq 'orphan.com' -and $null -eq $Parameters.account
            }
        }
    }

    It 'does not write when -WhatIf is supplied (ShouldProcess)' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionDnsMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'logs and skips a failing domain, keeps merging the rest of the fleet' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbNonQuery {
                if ($Parameters.domain -eq 'contoso.com') { throw 'contoso exploded' }
                1
            }
            $result = Invoke-ImperionDnsMerge
            $result.merged | Should -Be 1
            $result.failed | Should -Be 1
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Error' } -Times 1
        }
    }

    It 'is a clean no-op when no domains are governed' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionDnsDrift { @() }
            $result = Invoke-ImperionDnsMerge
            $result.domains | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }
}
