#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionMyItProcessRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionMyItProcessRequest' {
    It 'sends the api_token header (NOT the querystring) and unwraps the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'r1' }) } }
            }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://api.myitprocess.com/api/v1/recommendations' -PageSize 5
            $rows[0].id | Should -Be 'r1'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.api_token -eq 'tok' -and $Uri -notmatch 'api_token'
            }
        }
    }

    It 'walks pages until a short page ends the loop' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=1\b') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'b' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'c' }) } }
                }
            }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://api.myitprocess.com/api/v1/recommendations' -PageSize 2
            ($rows.id -join ',') | Should -Be 'a,b,c'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'tolerates a bare array body (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'z' }) } }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://api.myitprocess.com/api/v1/recommendations' -PageSize 5
            $rows[0].id | Should -Be 'z'
        }
    }
}
