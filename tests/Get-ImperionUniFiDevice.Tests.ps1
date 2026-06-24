#Requires -Modules Pester
# Hermetic tests for Get-ImperionUniFiDevice (#321, company-scope Site Manager). Only the UniFi
# HTTP layer is mocked; flatten/hash/site-mapping run for real. Pins: the CONFIRMED api.ui.com/v1
# device field shape (mac/ip/status/version/firmwareStatus/adoptionTime), hostId->site resolution
# from /v1/sites meta.name, and per-device account stamping from the site->account map.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionUniFiDevice (company Site Manager)' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog {} }
    }

    It 'maps the confirmed device shape, resolves the site, and stamps the mapped account' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionUniFiRequest {
                if ($Uri -match '/sites$') {
                    return @([pscustomobject]@{
                            siteId = 's1'; hostId = 'h1'; meta = [pscustomobject]@{ name = 'Acme HQ' }
                        })
                }
                , @([pscustomobject]@{
                        hostId   = 'h1'; hostName = 'Acme Console'
                        devices  = @([pscustomobject]@{
                                id = 'd1'; mac = 'AA:BB:CC'; name = 'Office Switch'; model = 'USW-24-POE'
                                ip = '10.0.0.2'; status = 'online'; version = '7.1.20'
                                firmwareStatus = 'upToDate'; adoptionTime = '2025-01-01T00:00:00Z'; isManaged = $true
                            })
                    })
            }

            $map = @{ 'Acme HQ' = '11111111-1111-1111-1111-111111111111' }
            $rows = @(Get-ImperionUniFiDevice -ApiKey 'k' -SiteAccountMap $map)

            $rows.Count                 | Should -Be 1
            $rows[0].name               | Should -Be 'Office Switch'
            $rows[0].mac                | Should -Be 'AA:BB:CC'
            $rows[0].ip_address         | Should -Be '10.0.0.2'
            $rows[0].site               | Should -Be 'Acme HQ'
            $rows[0].status             | Should -Be 'online'
            $rows[0].firmware_version   | Should -Be '7.1.20'
            $rows[0].firmware_updatable | Should -Be 'upToDate'
            $rows[0].adopted            | Should -Be '2025-01-01T00:00:00Z'
            $rows[0].source             | Should -Be 'unifi'
            $rows[0].external_id        | Should -Be 'd1'
            $rows[0].tenant_id          | Should -Be '11111111-1111-1111-1111-111111111111'
            $rows[0].content_hash       | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'stamps the all-zero sentinel tenant for a device whose site is not mapped' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionUniFiRequest {
                if ($Uri -match '/sites$') {
                    return @([pscustomobject]@{ siteId = 's2'; hostId = 'h2'; meta = [pscustomobject]@{ name = 'Unmapped Site' } })
                }
                , @([pscustomobject]@{
                        hostId  = 'h2'; hostName = 'Unmapped Console'
                        devices = @([pscustomobject]@{ id = 'd2'; mac = 'DD:EE'; name = 'AP'; status = 'online' })
                    })
            }

            $rows = @(Get-ImperionUniFiDevice -ApiKey 'k' -SiteAccountMap @{})
            $rows.Count        | Should -Be 1
            $rows[0].site      | Should -Be 'Unmapped Site'
            $rows[0].tenant_id | Should -Be '00000000-0000-0000-0000-000000000000'
        }
    }

    It 'falls back to the host name as the site when the host has no matching /sites entry' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionUniFiRequest {
                if ($Uri -match '/sites$') { return @() }   # no sites listed
                , @([pscustomobject]@{
                        hostId  = 'h3'; hostName = 'Beta Branch'
                        devices = @([pscustomobject]@{ id = 'd3'; mac = 'FF:00'; name = 'Branch AP'; status = 'online' })
                    })
            }

            $rows = @(Get-ImperionUniFiDevice -ApiKey 'k')
            $rows[0].site        | Should -Be 'Beta Branch'
            $rows[0].external_id | Should -Be 'd3'
        }
    }

    It 'returns nothing (and does not throw) when no devices exist' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionUniFiRequest { , @() }
            @(Get-ImperionUniFiDevice -ApiKey 'k') | Should -BeNullOrEmpty
        }
    }
}
