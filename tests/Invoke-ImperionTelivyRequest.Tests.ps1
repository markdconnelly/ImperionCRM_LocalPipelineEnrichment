#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionTelivyRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionTelivyRequest' {
    It 'sends a bearer token and returns the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'b' }); next = $null } }
            }
            $rows = Invoke-ImperionTelivyRequest -AccessToken 'tok123' -Uri 'https://api.telivy.com/v1/assessments'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.Authorization -eq 'Bearer tok123'
            }
        }
    }

    It 'follows the next cursor across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'cursor=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'c' }); next = $null } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'a' }); next = 'https://api.telivy.com/v1/assessments?cursor=2' } }
                }
            }
            $rows = Invoke-ImperionTelivyRequest -AccessToken 't' -Uri 'https://api.telivy.com/v1/assessments'
            ($rows.id -join ',') | Should -Be 'a,c'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'returns the body as a single item when the collection property is absent' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ id = 'solo'; name = 'one' } }
            }
            $rows = Invoke-ImperionTelivyRequest -AccessToken 't' -Uri 'https://api.telivy.com/v1/assessments/solo'
            $rows.Count | Should -Be 1
            $rows[0].id | Should -Be 'solo'
        }
    }

    It 'honors a custom items/next property name' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ results = @([pscustomobject]@{ id = 1 }); nextPage = $null } }
            }
            $rows = Invoke-ImperionTelivyRequest -AccessToken 't' -Uri 'https://api.telivy.com/x' -ItemsProperty 'results' -NextLinkProperty 'nextPage'
            $rows.Count | Should -Be 1
        }
    }
}
