#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionEasyDmarcRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionEasyDmarcRequest' {
    It 'sends a bearer api key and returns the data collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ name = 'a.com' }, [pscustomobject]@{ name = 'b.com' }) } }
            }
            $rows = Invoke-ImperionEasyDmarcRequest -ApiKey 'bear' -Uri 'https://api.easydmarc.com/domains'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer bear' }
        }
    }

    It 'walks ?page=N until a short page ends the loop' {
        InModuleScope ImperionPipeline {
            # PageSize 2: page 1 returns 2 (full -> continue), page 2 returns 1 (short -> stop).
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ name = 'c.com' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ name = 'a.com' }, [pscustomobject]@{ name = 'b.com' }) } }
                }
            }
            $rows = Invoke-ImperionEasyDmarcRequest -ApiKey 't' -Uri 'https://api.easydmarc.com/domains' -PageSize 2
            ($rows.name -join ',') | Should -Be 'a.com,b.com,c.com'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'stops at a reported meta.last_page even on a full page' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{
                        data = @([pscustomobject]@{ name = 'a.com' }, [pscustomobject]@{ name = 'b.com' })
                        meta = [pscustomobject]@{ last_page = 1 }
                    } }
            }
            $rows = Invoke-ImperionEasyDmarcRequest -ApiKey 't' -Uri 'https://api.easydmarc.com/domains' -PageSize 2
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1
        }
    }

    It 'does not throw when the body has no data array (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ name = 'solo.com' } } }
            { Invoke-ImperionEasyDmarcRequest -ApiKey 't' -Uri 'https://api.easydmarc.com/domains/solo.com' } | Should -Not -Throw
            $rows = Invoke-ImperionEasyDmarcRequest -ApiKey 't' -Uri 'https://api.easydmarc.com/domains/solo.com'
            $rows[0].name | Should -Be 'solo.com'
        }
    }
}
