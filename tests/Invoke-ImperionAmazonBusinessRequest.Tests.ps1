#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionAmazonBusinessRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionAmazonBusinessRequest' {
    It 'sends a bearer access token and returns the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ orderId = 'A1' }, [pscustomobject]@{ orderId = 'A2' }) } }
            }
            $rows = Invoke-ImperionAmazonBusinessRequest -AccessToken 'tok' -Uri 'https://na.business-api.amazon.com/orders/v1/orders'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer tok' }
        }
    }

    It 'walks the nextToken cursor until none is returned' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'nextToken=cur1') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ orderId = 'A3' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ orderId = 'A1' }, [pscustomobject]@{ orderId = 'A2' }); nextToken = 'cur1' } }
                }
            }
            $rows = Invoke-ImperionAmazonBusinessRequest -AccessToken 't' -Uri 'https://na.business-api.amazon.com/orders/v1/orders'
            ($rows.orderId -join ',') | Should -Be 'A1,A2,A3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'stops after one page when no nextToken is present' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ orderId = 'A1' }) } }
            }
            $rows = Invoke-ImperionAmazonBusinessRequest -AccessToken 't' -Uri 'https://na.business-api.amazon.com/orders/v1/orders'
            $rows.Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1
        }
    }

    It 'does not throw when the body has no data array (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ orderId = 'solo' } } }
            { Invoke-ImperionAmazonBusinessRequest -AccessToken 't' -Uri 'https://na.business-api.amazon.com/orders/v1/orders/solo' } | Should -Not -Throw
            $rows = Invoke-ImperionAmazonBusinessRequest -AccessToken 't' -Uri 'https://na.business-api.amazon.com/orders/v1/orders/solo'
            $rows[0].orderId | Should -Be 'solo'
        }
    }
}
