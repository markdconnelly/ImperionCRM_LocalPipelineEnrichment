#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionITGlueRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionITGlueRequest' {
    It 'pages a GET collection by following links.next' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page%5Bnumber%5D=2' -or $Uri -match 'page\[number\]=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = '3' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = '1' }, [pscustomobject]@{ id = '2' }); links = [pscustomobject]@{ next = 'https://api.itglue.com/organizations?page[number]=2' } } }
                }
            }
            $rows = Invoke-ImperionITGlueRequest -Path 'organizations' -ApiKey 'k'
            ($rows.id -join ',') | Should -Be '1,2,3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'does not throw on the last page when links is absent' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = '1' }) } } }
            $rows = Invoke-ImperionITGlueRequest -Path 'organizations' -ApiKey 'k'
            $rows.Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1
        }
    }

    It 'sends the x-api-key header and builds the base + query' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ data = @() } } }
            Invoke-ImperionITGlueRequest -Path 'organizations' -ApiKey 'secretkey' -Query 'page[size]=1000' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.'x-api-key' -eq 'secretkey' -and $Uri -eq 'https://api.itglue.com/organizations?page[size]=1000'
            }
        }
    }

    It 'returns the raw parsed body for a non-GET (write) request' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ data = [pscustomobject]@{ id = 'created-99' } } } }
            $result = Invoke-ImperionITGlueRequest -Path 'flexible_assets' -ApiKey 'k' -Method POST -Body @{ data = @{ type = 'flexible-assets' } }
            $result.data.id | Should -Be 'created-99'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
