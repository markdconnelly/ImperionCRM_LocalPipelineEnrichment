#Requires -Modules Pester
# Hermetic tests for the private helper Resolve-ImperionAccountTenant (#259): the owning-tenant
# isolation key for an account-scoped source. DB is mocked — no connection.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionAccountTenant' {
    It 'returns the mapped Microsoft tenant when account_tenant has one' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { [pscustomobject]@{ tenant_id = 'tenant-abc' } }
            Resolve-ImperionAccountTenant -Connection 'c' -AccountId 'acct-1' | Should -Be 'tenant-abc'
            Should -Invoke Invoke-ImperionDbQuery -Times 1 -ParameterFilter { $Sql -match 'FROM account_tenant' }
        }
    }

    It 'falls back to the account id when no tenant is mapped (always present, never partner)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Resolve-ImperionAccountTenant -Connection 'c' -AccountId 'acct-1' | Should -Be 'acct-1'
        }
    }
}
