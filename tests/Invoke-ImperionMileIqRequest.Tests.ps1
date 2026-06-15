#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionMileIqRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionMileIqRequest' {
    It 'sends a bearer header and skip/take paging params, never the token in the querystring' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ drives = @([pscustomobject]@{ id = '1' }) } } }
            $rows = Invoke-ImperionMileIqRequest -AccessToken 'tok' -Uri 'https://api.mileiq.com/drives?classification=business'
            $rows.Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.Authorization -eq 'Bearer tok' -and
                $Uri -match 'skip=0&take=' -and
                $Uri -notmatch 'tok'
            }
        }
    }

    It 'unwraps the { drives: [...] } wrapper' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ drives = @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'b' }) } } }
            $rows = Invoke-ImperionMileIqRequest -AccessToken 't' -Uri 'https://api.mileiq.com/drives' -PageSize 5
            ($rows.id -join ',') | Should -Be 'a,b'
        }
    }

    It 'tolerates a bare array body (pending live-shape verification)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'z' }) } }
            $rows = Invoke-ImperionMileIqRequest -AccessToken 't' -Uri 'https://api.mileiq.com/drives' -PageSize 5
            $rows[0].id | Should -Be 'z'
        }
    }

    It 'walks pages until a short page ends the loop, advancing skip' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'skip=0&') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ drives = @([pscustomobject]@{ id = 'p1' }, [pscustomobject]@{ id = 'p2' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ drives = @([pscustomobject]@{ id = 'p3' }) } }
                }
            }
            $rows = Invoke-ImperionMileIqRequest -AccessToken 't' -Uri 'https://api.mileiq.com/drives' -PageSize 2
            ($rows.id -join ',') | Should -Be 'p1,p2,p3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Uri -match 'skip=2&take=2' }
        }
    }

    It 'honors MaxPages as a hard cap' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ drives = @([pscustomobject]@{ id = 'q' }) } } }
            Invoke-ImperionMileIqRequest -AccessToken 't' -Uri 'https://api.mileiq.com/drives' -PageSize 1 -MaxPages 3 | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 3
        }
    }
}
