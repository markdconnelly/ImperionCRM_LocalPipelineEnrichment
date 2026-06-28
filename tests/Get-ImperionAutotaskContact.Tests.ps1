#Requires -Modules Pester
# Hermetic tests for Get-ImperionAutotaskContact: context helper + request layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskContact' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 't1' } }
            Mock Get-ImperionAutotaskContext { [pscustomobject]@{ Headers = @{}; ApiBase = 'https://ws/V1.0' } }
        }
    }

    It 'flattens contacts to the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest {
                , @([pscustomobject]@{ id = 7; companyID = 101; firstName = 'Ada'; lastName = 'Lovelace'; emailAddress = 'ada@acme.com'; isActive = $true })
            }
            $rows = Get-ImperionAutotaskContact
            $rows[0].first_name   | Should -Be 'Ada'
            $rows[0].email_address | Should -Be 'ada@acme.com'
            $rows[0].company_id   | Should -Be '101'
            $rows[0].source       | Should -Be 'autotask'
            $rows[0].external_id  | Should -Be '7'
        }
    }

    It 'does not throw when a contact omits optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @([pscustomobject]@{ id = 8; lastName = 'NoEmail' }) }
            { Get-ImperionAutotaskContact } | Should -Not -Throw
        }
    }

    It 'queries the Contacts entity with an incremental filter when -SinceDays is given' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @() }
            Get-ImperionAutotaskContact -SinceDays 7 | Out-Null
            Should -Invoke Invoke-ImperionAutotaskRequest -Times 1 -ParameterFilter { $Entity -eq 'Contacts' -and $Filter.field -eq 'lastActivityDate' }
        }
    }
}
