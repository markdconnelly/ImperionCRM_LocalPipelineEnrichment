#Requires -Modules Pester
# Hermetic tests for Get-ImperionDarkWebIdCompromise: DarkWebID request mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDarkWebIdCompromise' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
        }
    }

    It 'flattens compromises to the bronze envelope (source darkwebid) and joins exposedData' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDarkWebIdRequest {
                , @([pscustomobject]@{ id = 'x1'; email = 'sam@acme.com'; domain = 'acme.com'; breachSource = 'LinkedIn 2021'; dateFound = '2026-05-01'; passwordType = 'hashed'; exposedData = @('email', 'password') })
            }
            $rows = Get-ImperionDarkWebIdCompromise -Username 'u' -Password 'p'
            $rows[0].email         | Should -Be 'sam@acme.com'
            $rows[0].breach_source | Should -Be 'LinkedIn 2021'
            $rows[0].exposed_data  | Should -Be 'email; password'
            $rows[0].source        | Should -Be 'darkwebid'
            $rows[0].external_id   | Should -Be 'x1'
        }
    }

    It 'does not throw when a compromise omits exposedData' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDarkWebIdRequest { , @([pscustomobject]@{ id = 'x2'; email = 'bare@acme.com' }) }
            { Get-ImperionDarkWebIdCompromise -Username 'u' -Password 'p' } | Should -Not -Throw
            (Get-ImperionDarkWebIdCompromise -Username 'u' -Password 'p')[0].exposed_data | Should -BeNullOrEmpty
        }
    }

    It 'scopes the query to a domain when -Domain is given and threads the Basic-auth credentials' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDarkWebIdRequest { , @() }
            Get-ImperionDarkWebIdCompromise -Username 'u' -Password 'p' -Domain 'acme.com' | Out-Null
            Should -Invoke Invoke-ImperionDarkWebIdRequest -Times 1 -ParameterFilter {
                $Username -eq 'u' -and $Password -eq 'p' -and $Uri -match 'domain=acme.com'
            }
        }
    }

    It 'targets the secure.darkwebid.com base by default' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDarkWebIdRequest { , @() }
            Get-ImperionDarkWebIdCompromise -Username 'u' -Password 'p' | Out-Null
            Should -Invoke Invoke-ImperionDarkWebIdRequest -Times 1 -ParameterFilter {
                $Uri -like 'https://secure.darkwebid.com/*'
            }
        }
    }
}
