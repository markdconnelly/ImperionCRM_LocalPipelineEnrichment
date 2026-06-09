#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionAutotaskRequest. The HTTP core is mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionAutotaskRequest' {
    It 'returns all items and follows pageDetails.nextPageUrl across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ items = @([pscustomobject]@{ id = 3 }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ items = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }); pageDetails = [pscustomobject]@{ nextPageUrl = 'https://ws.autotask.net/atservicesrest/V1.0/Companies/query?page=2' } } }
                }
            }
            $rows = Invoke-ImperionAutotaskRequest -ApiBaseUrl 'https://ws.autotask.net/atservicesrest/V1.0' -Headers @{} -Entity 'Companies'
            $rows.Count | Should -Be 3
            ($rows.id -join ',') | Should -Be '1,2,3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'builds the query path with an url-encoded search filter' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ items = @(); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
            }
            Invoke-ImperionAutotaskRequest -ApiBaseUrl 'https://ws.autotask.net/atservicesrest/V1.0/' -Headers @{} -Entity 'Tickets' |
                Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -like 'https://ws.autotask.net/atservicesrest/V1.0/Tickets/query?search=*' -and $Uri -match '%22filter%22'
            }
        }
    }

    It 'passes a custom incremental filter through to the search payload' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ items = @(); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
            }
            $filter = @{ op = 'gte'; field = 'lastActivityDate'; value = '2026-01-01T00:00:00Z' }
            Invoke-ImperionAutotaskRequest -ApiBaseUrl 'https://ws.autotask.net/atservicesrest/V1.0' -Headers @{} -Entity 'Tickets' -Filter $filter |
                Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                [uri]::UnescapeDataString($Uri) -match 'lastActivityDate'
            }
        }
    }

    It 'does not throw when the response omits items or pageDetails (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ } } }
            { Invoke-ImperionAutotaskRequest -ApiBaseUrl 'https://ws.autotask.net/atservicesrest/V1.0' -Headers @{} -Entity 'Companies' } |
                Should -Not -Throw
            @(Invoke-ImperionAutotaskRequest -ApiBaseUrl 'https://ws.autotask.net/atservicesrest/V1.0' -Headers @{} -Entity 'Companies').Count |
                Should -Be 0
        }
    }
}
