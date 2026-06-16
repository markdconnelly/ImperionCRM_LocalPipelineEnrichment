#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionCdwRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionCdwRequest' {
    It 'sends a bearer api key and returns the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ orderNumber = 'O1' }, [pscustomobject]@{ orderNumber = 'O2' }) } }
            }
            $rows = Invoke-ImperionCdwRequest -ApiKey 'bear' -Uri 'https://api.cdw.com/orders/v1/orders'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer bear' }
        }
    }

    It 'walks ?page=N until a short page ends the loop' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ orderNumber = 'O3' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ orderNumber = 'O1' }, [pscustomobject]@{ orderNumber = 'O2' }) } }
                }
            }
            $rows = Invoke-ImperionCdwRequest -ApiKey 't' -Uri 'https://api.cdw.com/orders/v1/orders' -PageSize 2
            ($rows.orderNumber -join ',') | Should -Be 'O1,O2,O3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'stops at a reported meta.last_page even on a full page' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{
                        data = @([pscustomobject]@{ orderNumber = 'O1' }, [pscustomobject]@{ orderNumber = 'O2' })
                        meta = [pscustomobject]@{ last_page = 1 }
                    } }
            }
            $rows = Invoke-ImperionCdwRequest -ApiKey 't' -Uri 'https://api.cdw.com/orders/v1/orders' -PageSize 2
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1
        }
    }

    It 'does not throw when the body has no data array (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ orderNumber = 'solo' } } }
            { Invoke-ImperionCdwRequest -ApiKey 't' -Uri 'https://api.cdw.com/orders/v1/orders/solo' } | Should -Not -Throw
            $rows = Invoke-ImperionCdwRequest -ApiKey 't' -Uri 'https://api.cdw.com/orders/v1/orders/solo'
            $rows[0].orderNumber | Should -Be 'solo'
        }
    }
}
