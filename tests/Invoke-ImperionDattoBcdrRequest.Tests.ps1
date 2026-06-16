#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionDattoBcdrRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDattoBcdrRequest' {
    It 'sends a bearer header and unwraps the items collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ items = @([pscustomobject]@{ deviceUid = 'a' }, [pscustomobject]@{ deviceUid = 'b' }) } }
            }
            $rows = Invoke-ImperionDattoBcdrRequest -ApiKey 'k' -Uri 'https://api.datto.com/v1/bcdr/agents' -PageSize 5
            ($rows.deviceUid -join ',') | Should -Be 'a,b'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer k' }
        }
    }

    It 'walks pages until a short page ends the loop' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=1\b') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ items = @([pscustomobject]@{ deviceUid = 'p1' }, [pscustomobject]@{ deviceUid = 'p2' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ items = @([pscustomobject]@{ deviceUid = 'p3' }) } }
                }
            }
            $rows = Invoke-ImperionDattoBcdrRequest -ApiKey 'k' -Uri 'https://api.datto.com/v1/bcdr/agents' -PageSize 2
            ($rows.deviceUid -join ',') | Should -Be 'p1,p2,p3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'tolerates a bare array body (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @([pscustomobject]@{ deviceUid = 'z' }) } }
            $rows = Invoke-ImperionDattoBcdrRequest -ApiKey 'k' -Uri 'https://api.datto.com/v1/bcdr/agents' -PageSize 5
            $rows[0].deviceUid | Should -Be 'z'
        }
    }
}
