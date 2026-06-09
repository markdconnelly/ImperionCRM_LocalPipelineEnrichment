#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionDarkWebIdRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDarkWebIdRequest' {
    It 'sends a bearer api key and returns the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }) } }
            }
            $rows = Invoke-ImperionDarkWebIdRequest -ApiKey 'bear' -Uri 'https://api.darkwebid.com/compromises'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer bear' }
        }
    }

    It 'follows the JSON:API links.next cursor across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'p=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 9 }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 1 }); links = [pscustomobject]@{ next = 'https://api.darkwebid.com/compromises?p=2' } } }
                }
            }
            $rows = Invoke-ImperionDarkWebIdRequest -ApiKey 't' -Uri 'https://api.darkwebid.com/compromises'
            ($rows.id -join ',') | Should -Be '1,9'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'does not throw when neither data nor links is present (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ id = 'solo' } } }
            { Invoke-ImperionDarkWebIdRequest -ApiKey 't' -Uri 'https://api.darkwebid.com/compromises/solo' } | Should -Not -Throw
            $rows = Invoke-ImperionDarkWebIdRequest -ApiKey 't' -Uri 'https://api.darkwebid.com/compromises/solo'
            $rows[0].id | Should -Be 'solo'
        }
    }
}
