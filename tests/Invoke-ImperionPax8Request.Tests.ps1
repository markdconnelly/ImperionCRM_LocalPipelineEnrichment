#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionPax8Request. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionPax8Request' {
    It 'exchanges the client-credentials pair for a bearer, then GETs with that bearer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Method -eq 'POST') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 'bearer-xyz'; expires_in = 3600 } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ content = @([pscustomobject]@{ id = 'c1' }); page = [pscustomobject]@{ totalPages = 1; number = 0 } } }
                }
            }
            $rows = Invoke-ImperionPax8Request -ClientId 'id' -ClientSecret 'secret' -Path '/v1/companies'
            $rows.Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/oauth/token' }
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Method -eq 'GET' -and $Headers.Authorization -eq 'Bearer bearer-xyz' }
        }
    }

    It 'throws when the token exchange returns no access_token (fail loud)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ error = 'invalid_client' } } }
            { Invoke-ImperionPax8Request -ClientId 'id' -ClientSecret 'secret' -Path '/v1/companies' } |
                Should -Throw '*no access_token*'
        }
    }

    It 'walks Spring pages until page.number + 1 >= page.totalPages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Method -eq 'POST') { return [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 't' } } }
                if ($Uri -match 'page=1') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ content = @([pscustomobject]@{ id = 'c3' }); page = [pscustomobject]@{ totalPages = 2; number = 1 } } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ content = @([pscustomobject]@{ id = 'c1' }, [pscustomobject]@{ id = 'c2' }); page = [pscustomobject]@{ totalPages = 2; number = 0 } } }
                }
            }
            $rows = Invoke-ImperionPax8Request -ClientId 'id' -ClientSecret 'secret' -Path '/v1/companies'
            ($rows.id -join ',') | Should -Be 'c1,c2,c3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2 -ParameterFilter { $Method -eq 'GET' }
        }
    }

    It 'tolerates a bare array body and stops on a short page (no wrapper)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Method -eq 'POST') { return [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 't' } } }
                [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'bare' }) }
            }
            $rows = Invoke-ImperionPax8Request -ClientId 'id' -ClientSecret 'secret' -Path '/v1/orders'
            $rows[0].id | Should -Be 'bare'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Method -eq 'GET' }
        }
    }
}
