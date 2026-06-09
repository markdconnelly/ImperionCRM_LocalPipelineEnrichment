#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionArmRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionArmRequest' {
    It 'returns all items and follows nextLink across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'skip') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ value = @([pscustomobject]@{ id = '/subs/3' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ value = @([pscustomobject]@{ id = '/subs/1' }); nextLink = 'https://management.azure.com/subscriptions?$skip=1' } }
                }
            }
            $rows = Invoke-ImperionArmRequest -Path '/subscriptions?api-version=2022-12-01' -AccessToken 't'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'does not throw when the body has no value or nextLink (single resource)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ id = '/subs/x'; name = 'x' } } }
            $rows = Invoke-ImperionArmRequest -Path '/subscriptions/x?api-version=2022-12-01' -AccessToken 't'
            $rows.Count | Should -Be 1
            $rows[0].name | Should -Be 'x'
        }
    }

    It 'expands a relative path to the management base and sends the bearer token' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ value = @() } } }
            Invoke-ImperionArmRequest -Path '/subscriptions?api-version=2022-12-01' -AccessToken 'tok' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -eq 'https://management.azure.com/subscriptions?api-version=2022-12-01' -and $Headers.Authorization -eq 'Bearer tok'
            }
        }
    }

    It 'passes a full URL through unchanged' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ value = @() } } }
            Invoke-ImperionArmRequest -Path 'https://management.azure.com/tenants?api-version=2022-12-01' -AccessToken 't' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -eq 'https://management.azure.com/tenants?api-version=2022-12-01'
            }
        }
    }
}
