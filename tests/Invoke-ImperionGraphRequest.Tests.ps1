#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionGraphRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionGraphRequest' {
    It 'returns all items and follows @odata.nextLink across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'skiptoken') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 3 }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc' } }
                }
            }
            $rows = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/users' -AccessToken 't'
            ($rows.id -join ',') | Should -Be '1,2,3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'does not throw when the body has no value or nextLink (single resource)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ id = 'me'; displayName = 'Mark' } } }
            $rows = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/me' -AccessToken 't'
            $rows.Count | Should -Be 1
            $rows[0].id | Should -Be 'me'
        }
    }

    It 'sends the bearer token and ConsistencyLevel header' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ value = @() } } }
            Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/users' -AccessToken 'tok' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.Authorization -eq 'Bearer tok' -and $Headers.ConsistencyLevel -eq 'eventual'
            }
        }
    }

    It 'expands a relative path and appends $select' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ value = @() } } }
            Invoke-ImperionGraphRequest -Uri 'users' -AccessToken 't' -Select 'id,displayName' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/users?$select=id,displayName'
            }
        }
    }
}
