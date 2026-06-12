#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionKqmRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionKqmRequest' {
    It 'appends apikey and page to the querystring' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'q1' }) } }
            $rows = Invoke-ImperionKqmRequest -ApiKey 'k1' -Uri 'https://api.kaseyaquotemanager.com/v1/quote'
            $rows.Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.kaseyaquotemanager.com/v1/quote?page=1&apikey=k1'
            }
        }
    }

    It 'uses & when the URI already has a querystring (modifiedAfter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @() } }
            Invoke-ImperionKqmRequest -ApiKey 'k1' -Uri 'https://x/v1/quote?modifiedAfter=2026-01-01' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -eq 'https://x/v1/quote?modifiedAfter=2026-01-01&page=1&apikey=k1'
            }
        }
    }

    It 'walks pages until a short page ends the loop' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=1&') {
                    # full page (PageSize 2 for the test) -> keep going
                    [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'q1' }, [pscustomobject]@{ id = 'q2' }) }
                }
                else {
                    [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'q3' }) }   # short page -> stop
                }
            }
            $rows = Invoke-ImperionKqmRequest -ApiKey 'k' -Uri 'https://x/v1/quote' -PageSize 2
            ($rows.id -join ',') | Should -Be 'q1,q2,q3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'honors MaxPages as a hard cap' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'q' }) } }
            Invoke-ImperionKqmRequest -ApiKey 'k' -Uri 'https://x/v1/quote' -PageSize 1 -MaxPages 3 | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 3
        }
    }

    It 'url-encodes the api key' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @() } }
            Invoke-ImperionKqmRequest -ApiKey 'k 1&x' -Uri 'https://x/v1/quote' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Uri -match 'apikey=k%201%26x$' }
        }
    }
}
