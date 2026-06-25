#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionDarkWebIdRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDarkWebIdRequest' {
    It 'sends an HTTP Basic auth header (base64 of username:password) and returns the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }) } }
            }
            $rows = Invoke-ImperionDarkWebIdRequest -Username 'user' -Password 'pass' -Uri 'https://secure.darkwebid.com/compromises'
            $rows.Count | Should -Be 2
            $expected = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('user:pass'))
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq $expected }
            # And it is NOT a bearer header.
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -notlike 'Bearer*' }
            # The decoded credential round-trips to the exact pair.
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $b64 = ($Headers.Authorization -replace '^Basic ', '')
                [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) -eq 'user:pass'
            }
        }
    }

    It 'follows the JSON:API links.next cursor across pages' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'p=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 9 }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 1 }); links = [pscustomobject]@{ next = 'https://secure.darkwebid.com/compromises?p=2' } } }
                }
            }
            $rows = Invoke-ImperionDarkWebIdRequest -Username 'u' -Password 'p' -Uri 'https://secure.darkwebid.com/compromises'
            ($rows.id -join ',') | Should -Be '1,9'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'does not throw when neither data nor links is present (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ id = 'solo' } } }
            { Invoke-ImperionDarkWebIdRequest -Username 'u' -Password 'p' -Uri 'https://secure.darkwebid.com/compromises/solo' } | Should -Not -Throw
            $rows = Invoke-ImperionDarkWebIdRequest -Username 'u' -Password 'p' -Uri 'https://secure.darkwebid.com/compromises/solo'
            $rows[0].id | Should -Be 'solo'
        }
    }
}
