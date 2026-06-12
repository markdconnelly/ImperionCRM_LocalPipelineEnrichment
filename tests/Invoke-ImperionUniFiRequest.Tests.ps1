#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionUniFiRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionUniFiRequest' {
    It 'sends the X-API-Key header and returns the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'd1' }, [pscustomobject]@{ id = 'd2' }) } }
            }
            $rows = Invoke-ImperionUniFiRequest -ApiKey 'k1' -Uri 'https://api.ui.com/v1/devices'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.'X-API-Key' -eq 'k1' }
        }
    }

    It 'follows the cloud nextToken cursor across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'nextToken=tok2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'd9' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'd1' }); nextToken = 'tok2' } }
                }
            }
            $rows = Invoke-ImperionUniFiRequest -ApiKey 'k' -Uri 'https://api.ui.com/v1/devices'
            ($rows.id -join ',') | Should -Be 'd1,d9'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Uri -eq 'https://api.ui.com/v1/devices?nextToken=tok2' }
        }
    }

    It 'follows console offset paging until totalCount is reached' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'offset=1') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'd2' }); offset = 1; count = 1; totalCount = 2 } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'd1' }); offset = 0; count = 1; totalCount = 2 } }
                }
            }
            $rows = Invoke-ImperionUniFiRequest -ApiKey 'k' -Uri 'https://unifi.acme.local/proxy/network/integration/v1/sites/s1/devices'
            ($rows.id -join ',') | Should -Be 'd1,d2'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'does not throw on a single non-paged resource (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ id = 'solo' } } }
            $rows = Invoke-ImperionUniFiRequest -ApiKey 'k' -Uri 'https://api.ui.com/v1/devices/solo'
            $rows[0].id | Should -Be 'solo'
        }
    }
}
