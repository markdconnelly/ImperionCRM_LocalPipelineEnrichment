#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionDarkWebIdRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDarkWebIdRequest' {
    It 'sends a bearer token and returns the collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }); next = $null } }
            }
            $rows = Invoke-ImperionDarkWebIdRequest -AccessToken 'bear' -Uri 'https://api.example/v1/compromises'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer bear' }
        }
    }

    It 'follows the next cursor across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'p=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 9 }); next = $null } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 1 }); next = 'https://api.example/v1/compromises?p=2' } }
                }
            }
            $rows = Invoke-ImperionDarkWebIdRequest -AccessToken 't' -Uri 'https://api.example/v1/compromises'
            ($rows.id -join ',') | Should -Be '1,9'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'returns the body as a single item when the collection property is absent' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ id = 'solo' } } }
            $rows = Invoke-ImperionDarkWebIdRequest -AccessToken 't' -Uri 'https://api.example/v1/compromises/solo'
            $rows.Count | Should -Be 1
            $rows[0].id | Should -Be 'solo'
        }
    }
}
