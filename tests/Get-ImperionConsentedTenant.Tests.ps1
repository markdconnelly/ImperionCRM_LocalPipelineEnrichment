#Requires -Modules Pester
# Hermetic tests for Get-ImperionConsentedTenant (#358, ADR-0030 Decision #4): the registry
# enumeration that lists the consented tenants this node hydrates. The DB layer is mocked — no
# live connection — so this asserts the query is issued and the rows are projected to a string[].

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionConsentedTenant' {
    It 'projects account_tenant join connection rows to a string[] of tenant ids' {
        InModuleScope ImperionPipeline {
            $script:disposed = $false
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed = $true }
            }
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{ tenant_id = '49307c12' },
                    [pscustomobject]@{ tenant_id = 'bb2a08c8' }
                )
            }

            $tenants = Get-ImperionConsentedTenant

            $tenants | Should -Be @('49307c12', 'bb2a08c8')
            # It opened its own connection and disposed it.
            Should -Invoke New-ImperionDbConnection -Times 1
            $script:disposed | Should -BeTrue
        }
    }

    It 'returns an empty array when nothing is mapped yet (dormant-safe for the caller)' {
        InModuleScope ImperionPipeline {
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value {}
            }
            Mock Invoke-ImperionDbQuery { @() }

            $tenants = @(Get-ImperionConsentedTenant)
            $tenants.Count | Should -Be 0
        }
    }

    It 'reuses a supplied -Connection and does not open or dispose its own' {
        InModuleScope ImperionPipeline {
            Mock New-ImperionDbConnection { throw 'must not open a connection when one is supplied' }
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ tenant_id = 'd3f6481e' }) }
            $supplied = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { throw 'must not dispose a supplied connection' }

            $tenants = Get-ImperionConsentedTenant -Connection $supplied

            $tenants | Should -Be @('d3f6481e')
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }
}
