#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionCloudResourceSync (#234): the estate fan-out over the
# account_tenant registry. DB, collector, and bronze writer are mocked — no live ARM/DB.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionCloudResourceSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:fakeConn = [pscustomobject]@{ disposed = $false }
            $script:fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.disposed = $true } -Force
            Mock New-ImperionDbConnection { $script:fakeConn }
            Mock Write-ImperionLog {}
            Mock Set-ImperionCloudResourceToBronze {}
            Mock Get-ImperionCloudResource { @([pscustomobject]@{ entity = 'subscriptions'; tenant_id = $TenantId }) }
        }
    }

    It 'fans out over every registered client tenant from account_tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{ tenant_id = 'tenant-a' }, [pscustomobject]@{ tenant_id = 'tenant-b' })
            }
            Invoke-ImperionCloudResourceSync

            Should -Invoke Get-ImperionCloudResource -Times 1 -ParameterFilter { $TenantId -eq 'tenant-a' }
            Should -Invoke Get-ImperionCloudResource -Times 1 -ParameterFilter { $TenantId -eq 'tenant-b' }
            Should -Invoke Set-ImperionCloudResourceToBronze -Times 2
            $script:fakeConn.disposed | Should -BeTrue
        }
    }

    It 'reads the account_tenant registry (not an env var)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Invoke-ImperionCloudResourceSync
            Should -Invoke Invoke-ImperionDbQuery -Times 1 -ParameterFilter { $Sql -match 'FROM account_tenant' }
        }
    }

    It 'is dormant-safe: with no registered tenants it sweeps the partner tenant only' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Invoke-ImperionCloudResourceSync
            # Partner fallback: collector invoked once with no explicit TenantId.
            Should -Invoke Get-ImperionCloudResource -Times 1
            Should -Invoke Get-ImperionCloudResource -Times 1 -ParameterFilter { -not $TenantId }
        }
    }

    It 'skips a failing tenant and continues (fail-closed, per-tenant isolation)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{ tenant_id = 'bad' }, [pscustomobject]@{ tenant_id = 'good' })
            }
            Mock Get-ImperionCloudResource {
                if ($TenantId -eq 'bad') { throw 'no consent' }
                @([pscustomobject]@{ entity = 'subscriptions'; tenant_id = $TenantId })
            }
            { Invoke-ImperionCloudResourceSync } | Should -Not -Throw
            Should -Invoke Set-ImperionCloudResourceToBronze -Times 1   # only the good tenant wrote
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }
}
