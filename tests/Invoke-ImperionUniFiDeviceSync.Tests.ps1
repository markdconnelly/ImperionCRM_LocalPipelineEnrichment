#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionUniFiDeviceSync (#259): the multi-console fan-out over the
# `connection` credential registry. DB, resolver, collector, and bronze writer are mocked — no
# live UniFi / DB / Key Vault. Pins: per-console enumeration from the registry, the api-key +
# provider_config resolution, the console|cloud branch, owning-tenant stamping, and fail-closed
# per-console isolation.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionUniFiDeviceSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:fakeConn = [pscustomobject]@{ disposed = $false }
            $script:fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.disposed = $true } -Force
            Mock New-ImperionDbConnection { $script:fakeConn }
            Mock Write-ImperionLog {}
            Mock Set-ImperionUniFiDeviceToBronze {}
            Mock Get-ImperionUniFiDevice { @([pscustomobject]@{ external_id = 'd1'; tenant_id = $TenantId }) }
            Mock Resolve-ImperionTenantCredential { @{ ApiKey = "key-for-$AccountId" } }
            Mock Resolve-ImperionAccountTenant { "tenant-of-$AccountId" }
        }
    }

    It 'enumerates active client UniFi consoles from the connection registry' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Invoke-ImperionUniFiDeviceSync
            Should -Invoke Invoke-ImperionDbQuery -Times 1 -ParameterFilter {
                $Sql -match 'FROM connection' -and $Sql -match "provider = 'unifi'" -and $Sql -match "scope = 'client'"
            }
        }
    }

    It 'fans out over every registered console, resolving each key + config' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{ account_id = 'acct-a'; external_account_id = 'console-a'; provider_config = '{"connectionType":"console","controllerHost":"a.local"}' },
                    [pscustomobject]@{ account_id = 'acct-b'; external_account_id = 'console-b'; provider_config = '{"connectionType":"cloud"}' }
                )
            }
            Invoke-ImperionUniFiDeviceSync

            # Console A → Network Integration API with its host.
            Should -Invoke Get-ImperionUniFiDevice -Times 1 -ParameterFilter {
                $ConnectionType -eq 'console' -and $ControllerHost -eq 'a.local' -and $ApiKey -eq 'key-for-acct-a'
            }
            # Console B → cloud, no host.
            Should -Invoke Get-ImperionUniFiDevice -Times 1 -ParameterFilter {
                $ConnectionType -eq 'cloud' -and -not $ControllerHost -and $ApiKey -eq 'key-for-acct-b'
            }
            Should -Invoke Set-ImperionUniFiDeviceToBronze -Times 2
            $script:fakeConn.disposed | Should -BeTrue
        }
    }

    It 'stamps the owning tenant on each console (per-tenant isolation)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{ account_id = 'acct-a'; external_account_id = 'console-a'; provider_config = '{"connectionType":"cloud"}' })
            }
            Invoke-ImperionUniFiDeviceSync
            Should -Invoke Resolve-ImperionAccountTenant -Times 1 -ParameterFilter { $AccountId -eq 'acct-a' }
            Should -Invoke Get-ImperionUniFiDevice -Times 1 -ParameterFilter { $TenantId -eq 'tenant-of-acct-a' }
        }
    }

    It 'is dormant-safe: with no registered consoles it logs and no-ops (no resolve, no poll)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Invoke-ImperionUniFiDeviceSync
            Should -Invoke Resolve-ImperionTenantCredential -Times 0
            Should -Invoke Get-ImperionUniFiDevice -Times 0
            $script:fakeConn.disposed | Should -BeTrue
        }
    }

    It 'skips a console whose credential cannot be resolved and continues (fail-closed)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{ account_id = 'bad'; external_account_id = 'console-bad'; provider_config = '{"connectionType":"cloud"}' },
                    [pscustomobject]@{ account_id = 'good'; external_account_id = 'console-good'; provider_config = '{"connectionType":"cloud"}' }
                )
            }
            Mock Resolve-ImperionTenantCredential {
                if ($AccountId -eq 'bad') { throw 'no active client connection (no consent)' }
                @{ ApiKey = 'key-good' }
            }
            { Invoke-ImperionUniFiDeviceSync } | Should -Not -Throw
            Should -Invoke Set-ImperionUniFiDeviceToBronze -Times 1   # only the good console wrote
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }

    It 'skips a console with no provider_config.connectionType (registration error)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{ account_id = 'acct'; external_account_id = 'console-x'; provider_config = $null })
            }
            { Invoke-ImperionUniFiDeviceSync } | Should -Not -Throw
            Should -Invoke Get-ImperionUniFiDevice -Times 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }
}
