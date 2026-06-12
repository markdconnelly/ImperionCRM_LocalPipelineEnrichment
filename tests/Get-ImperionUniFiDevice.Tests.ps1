#Requires -Modules Pester
# Hermetic tests for Get-ImperionUniFiDevice: config + UniFi requests mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionUniFiDevice' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Write-ImperionLog {}
        }
    }

    Context 'console (Network Integration API)' {
        It 'enumerates sites then devices, stamping the owning site, source unifi' {
            InModuleScope ImperionPipeline {
                Mock Invoke-ImperionUniFiRequest {
                    if ($Uri -match '/sites$') {
                        return @([pscustomobject]@{ id = 'site-1'; name = 'Acme HQ' })
                    }
                    @([pscustomobject]@{
                        id = 'dev-1'; name = 'Office Switch'; model = 'USW-24-POE'; macAddress = 'AA:BB'
                        ipAddress = '10.0.0.2'; state = 'ONLINE'; firmwareVersion = '7.1.20'
                        firmwareUpdatable = $true; adoptedAt = '2025-01-01'; lastSeen = '2026-06-11'
                    })
                }
                $rows = @(Get-ImperionUniFiDevice -ApiKey 'k' -ConnectionType console -ControllerHost 'unifi.acme.local')
                $rows.Count                  | Should -Be 1
                $rows[0].name                | Should -Be 'Office Switch'
                $rows[0].mac                 | Should -Be 'AA:BB'
                $rows[0].site                | Should -Be 'Acme HQ'
                $rows[0].status              | Should -Be 'ONLINE'
                $rows[0].firmware_updatable  | Should -Be 'True'
                $rows[0].source              | Should -Be 'unifi'
                $rows[0].tenant_id           | Should -Be 'partner'
                $rows[0].external_id         | Should -Be 'dev-1'
                $rows[0].content_hash        | Should -Match '^[0-9a-f]{64}$'
                Should -Invoke Invoke-ImperionUniFiRequest -ParameterFilter { $Uri -eq 'https://unifi.acme.local/proxy/network/integration/v1/sites/site-1/devices' }
            }
        }

        It 'requires -ControllerHost' {
            InModuleScope ImperionPipeline {
                { Get-ImperionUniFiDevice -ApiKey 'k' -ConnectionType console } | Should -Throw '*ControllerHost*'
            }
        }
    }

    Context 'cloud (Site Manager API)' {
        It 'unwraps per-host device groups and stamps the host as the site' {
            InModuleScope ImperionPipeline {
                Mock Invoke-ImperionUniFiRequest {
                    , @([pscustomobject]@{
                        hostName = 'Beta Branch'
                        devices  = @([pscustomobject]@{ id = 'dev-2'; name = 'Branch AP'; model = 'U6-Lite'; macAddress = 'CC:DD'; state = 'ONLINE' })
                    })
                }
                $rows = @(Get-ImperionUniFiDevice -ApiKey 'k' -ConnectionType cloud)
                $rows.Count          | Should -Be 1
                $rows[0].name        | Should -Be 'Branch AP'
                $rows[0].site        | Should -Be 'Beta Branch'
                $rows[0].external_id | Should -Be 'dev-2'
                Should -Invoke Invoke-ImperionUniFiRequest -ParameterFilter { $Uri -eq 'https://api.ui.com/v1/devices' }
            }
        }

        It 'returns nothing (and does not throw) when no devices exist' {
            InModuleScope ImperionPipeline {
                Mock Invoke-ImperionUniFiRequest { , @() }
                @(Get-ImperionUniFiDevice -ApiKey 'k' -ConnectionType cloud) | Should -BeNullOrEmpty
            }
        }
    }
}
