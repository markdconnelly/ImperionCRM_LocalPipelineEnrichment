#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionUniFiDeviceSync (#321, company-scope Site Manager). DB,
# credential resolver, collector, and bronze writer are mocked — no live UniFi / DB / Key Vault.
# Pins: the ONE company key resolve, the entity_xref site->account map handed to the collector,
# the bronze write, and dormant-safety when the company key is not connected.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionUniFiDeviceSync (company Site Manager)' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:fakeConn = [pscustomobject]@{ disposed = $false }
            $script:fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.disposed = $true } -Force
            Mock New-ImperionDbConnection { $script:fakeConn }
            Mock Write-ImperionLog {}
            Mock Set-ImperionUniFiDeviceToBronze {}
            Mock Get-ImperionUniFiDevice { @([pscustomobject]@{ external_id = 'd1'; tenant_id = 'acct-a' }) }
            Mock Resolve-ImperionCompanyCredential { 'company-site-manager-key' }
            Mock Invoke-ImperionDbQuery { @() }
        }
    }

    It 'resolves the ONE company Site Manager key and sweeps with it' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionUniFiDeviceSync
            Should -Invoke Resolve-ImperionCompanyCredential -Times 1 -ParameterFilter {
                $Provider -eq 'unifi' -and $Field -eq 'apiKey'
            }
            Should -Invoke Get-ImperionUniFiDevice -Times 1 -ParameterFilter { $ApiKey -eq 'company-site-manager-key' }
            Should -Invoke Set-ImperionUniFiDeviceToBronze -Times 1
            $script:fakeConn.disposed | Should -BeTrue
        }
    }

    It 'reads the entity_xref site->account map and hands it to the collector' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{ source_key = 'Acme HQ'; account_id = 'acct-a' })
            }
            Invoke-ImperionUniFiDeviceSync
            Should -Invoke Invoke-ImperionDbQuery -Times 1 -ParameterFilter {
                $Sql -match 'FROM entity_xref' -and $Sql -match "source_system = 'unifi'"
            }
            Should -Invoke Get-ImperionUniFiDevice -Times 1 -ParameterFilter {
                $SiteAccountMap['Acme HQ'] -eq 'acct-a'
            }
        }
    }

    It 'is dormant-safe: with no company key it logs and no-ops (no xref read, no poll, no write)' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionCompanyCredential { $null }
            Invoke-ImperionUniFiDeviceSync
            Should -Invoke Invoke-ImperionDbQuery -Times 0
            Should -Invoke Get-ImperionUniFiDevice -Times 0
            Should -Invoke Set-ImperionUniFiDeviceToBronze -Times 0
            $script:fakeConn.disposed | Should -BeTrue
        }
    }

    It 'does not write bronze when the estate returns no devices' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionUniFiDevice { @() }
            Invoke-ImperionUniFiDeviceSync
            Should -Invoke Set-ImperionUniFiDeviceToBronze -Times 0
            $script:fakeConn.disposed | Should -BeTrue
        }
    }
}
