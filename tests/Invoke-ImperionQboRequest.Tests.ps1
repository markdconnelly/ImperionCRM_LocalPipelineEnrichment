#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionQboRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionQboRequest' {
    It 'builds the realm-scoped query URL with STARTPOSITION/MAXRESULTS and a bearer header' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ QueryResponse = [pscustomobject]@{ BillPayment = @([pscustomobject]@{ Id = '1' }) } } }
            }
            $rows = Invoke-ImperionQboRequest -AccessToken 'tok' -RealmId '12345' -Query 'SELECT * FROM BillPayment' -EntityProperty 'BillPayment'
            $rows.Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -match '/v3/company/12345/query\?query=' -and
                $Uri -match 'STARTPOSITION%201%20MAXRESULTS%20100' -and
                $Headers.Authorization -eq 'Bearer tok'
            }
        }
    }

    It 'unwraps QueryResponse.<Entity> rows' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ QueryResponse = [pscustomobject]@{ BillPayment = @([pscustomobject]@{ Id = 'a' }, [pscustomobject]@{ Id = 'b' }) } } }
            }
            $rows = Invoke-ImperionQboRequest -AccessToken 't' -RealmId 'r' -Query 'SELECT * FROM BillPayment' -EntityProperty 'BillPayment' -PageSize 5
            ($rows.Id -join ',') | Should -Be 'a,b'
        }
    }

    It 'tolerates a bare array body (pending live-shape verification)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ BillPayment = @([pscustomobject]@{ Id = 'z' }) } } }
            $rows = Invoke-ImperionQboRequest -AccessToken 't' -RealmId 'r' -Query 'SELECT * FROM BillPayment' -EntityProperty 'BillPayment' -PageSize 5
            $rows[0].Id | Should -Be 'z'
        }
    }

    It 'walks pages until a short page ends the loop, advancing STARTPOSITION' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'STARTPOSITION%201%20') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ QueryResponse = [pscustomobject]@{ BillPayment = @([pscustomobject]@{ Id = 'p1' }, [pscustomobject]@{ Id = 'p2' }) } } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ QueryResponse = [pscustomobject]@{ BillPayment = @([pscustomobject]@{ Id = 'p3' }) } } }
                }
            }
            $rows = Invoke-ImperionQboRequest -AccessToken 't' -RealmId 'r' -Query 'SELECT * FROM BillPayment' -EntityProperty 'BillPayment' -PageSize 2
            ($rows.Id -join ',') | Should -Be 'p1,p2,p3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Uri -match 'STARTPOSITION%203%20MAXRESULTS%202' }
        }
    }

    It 'honors MaxPages as a hard cap' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ QueryResponse = [pscustomobject]@{ BillPayment = @([pscustomobject]@{ Id = 'q' }) } } }
            }
            Invoke-ImperionQboRequest -AccessToken 't' -RealmId 'r' -Query 'SELECT * FROM BillPayment' -EntityProperty 'BillPayment' -PageSize 1 -MaxPages 3 | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 3
        }
    }
}
