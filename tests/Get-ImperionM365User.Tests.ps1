#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365User: Graph token + request mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionM365User' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
        }
    }

    It 'flattens users to the standard bronze envelope and joins businessPhones' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @([pscustomobject]@{ id = 'u1'; displayName = 'Ada'; userPrincipalName = 'ada@imperionllc.com'; mail = 'ada@imperionllc.com'; accountEnabled = $true; businessPhones = @('555-1', '555-2') })
            }
            $rows = Get-ImperionM365User
            $rows[0].display_name    | Should -Be 'Ada'
            $rows[0].upn             | Should -Be 'ada@imperionllc.com'
            $rows[0].business_phones | Should -Be '555-1; 555-2'
            $rows[0].account_enabled | Should -Be 'true'
            $rows[0].source          | Should -Be 'm365'
            $rows[0].external_id     | Should -Be 'u1'
        }
    }

    It 'does not throw when a user omits optional fields (e.g. no businessPhones)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'u2'; displayName = 'Bare' }) }
            { Get-ImperionM365User } | Should -Not -Throw
            (Get-ImperionM365User)[0].business_phones | Should -BeNullOrEmpty
        }
    }

    It 'mints a Graph token for the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionM365User -TenantId 'customer-1' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-1' }
        }
    }
}
