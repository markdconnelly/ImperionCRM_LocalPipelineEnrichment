#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionAutotaskZone. The HTTP core (Invoke-ImperionRestWithRetry)
# is mocked inside the module scope, so no network is touched. Run: Invoke-Pester ./tests

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskZone' {
    BeforeEach {
        InModuleScope ImperionPipeline { $script:ImperionAutotaskZoneCache = @{} }
    }

    It 'returns the discovered zone url with the /V1.0 suffix' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ url = 'https://webservices15.autotask.net/atservicesrest/' } }
            }
            $result = Get-ImperionAutotaskZone -UserName 'api@imperion' -Headers @{ UserName = 'api@imperion' } -Force
            $result | Should -Be 'https://webservices15.autotask.net/atservicesrest/V1.0'
        }
    }

    It 'escapes the user name into the discovery query string' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ url = 'https://x.autotask.net/atservicesrest' } }
            }
            Get-ImperionAutotaskZone -UserName 'a b+c@imperion' -Headers @{} -Force | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -match 'user=a%20b%2Bc%40imperion'
            }
        }
    }

    It 'caches per user so discovery runs only once' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ url = 'https://ws.autotask.net/atservicesrest' } }
            }
            Get-ImperionAutotaskZone -UserName 'u1' -Headers @{} | Out-Null
            Get-ImperionAutotaskZone -UserName 'u1' -Headers @{} | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1
        }
    }

    It 'throws when zoneInformation returns no url (null value)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ url = $null } } }
            { Get-ImperionAutotaskZone -UserName 'u2' -Headers @{} -Force } | Should -Throw '*no url*'
        }
    }

    It 'throws (not a StrictMode error) when the body omits url entirely' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ } } }
            { Get-ImperionAutotaskZone -UserName 'u3' -Headers @{} -Force } | Should -Throw '*no url*'
        }
    }
}
