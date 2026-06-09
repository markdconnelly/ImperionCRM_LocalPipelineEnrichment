#Requires -Modules Pester
# Hermetic tests for Get-ImperionAutotaskContract: context helper + request layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskContract' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionAutotaskContext { [pscustomobject]@{ Headers = @{}; ApiBase = 'https://ws/V1.0' } }
        }
    }

    It 'flattens contracts to the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest {
                , @([pscustomobject]@{ id = 55; contractName = 'Managed Services'; companyID = 101; status = 1; lastModifiedDateTime = '2026-06-01T00:00:00Z' })
            }
            $rows = Get-ImperionAutotaskContract
            $rows[0].contract_name | Should -Be 'Managed Services'
            $rows[0].company_id    | Should -Be '101'
            $rows[0].source        | Should -Be 'autotask'
            $rows[0].external_id   | Should -Be '55'
        }
    }

    It 'does not throw when a contract omits optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @([pscustomobject]@{ id = 56; contractName = 'Bare' }) }
            { Get-ImperionAutotaskContract } | Should -Not -Throw
        }
    }

    It 'queries Contracts incrementally on lastModifiedDateTime when -SinceDays is given' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @() }
            Get-ImperionAutotaskContract -SinceDays 30 | Out-Null
            Should -Invoke Invoke-ImperionAutotaskRequest -Times 1 -ParameterFilter { $Entity -eq 'Contracts' -and $Filter.field -eq 'lastModifiedDateTime' }
        }
    }
}
