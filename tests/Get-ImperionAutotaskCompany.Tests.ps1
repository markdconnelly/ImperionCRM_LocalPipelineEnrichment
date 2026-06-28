#Requires -Modules Pester
# Hermetic tests for Get-ImperionAutotaskCompany: secrets + the connect layer are mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskCompany' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 't1' } }
            Mock Get-ImperionSecretNames { @{ AutotaskUserName = 'autotask-username'; AutotaskIntegrationCode = 'autotask-integration-code'; AutotaskSecret = 'autotask-secret' } }
            Mock Get-ImperionSecretValue { 'secret' }
            Mock Get-ImperionAutotaskZone { 'https://ws.autotask.net/atservicesrest/V1.0' }
        }
    }

    It 'flattens companies to the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest {
                , @([pscustomobject]@{ id = 101; companyName = 'Acme Co'; companyNumber = 'A-1'; isActive = $true; lastActivityDate = '2026-06-01T00:00:00Z' })
            }
            $rows = Get-ImperionAutotaskCompany
            $rows.Count        | Should -Be 1
            $rows[0].company_name | Should -Be 'Acme Co'
            $rows[0].is_active    | Should -Be 'true'
            $rows[0].source       | Should -Be 'autotask'
            $rows[0].tenant_id    | Should -Be 't1'
            $rows[0].external_id  | Should -Be '101'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'does not throw when a company omits optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @([pscustomobject]@{ id = 102; companyName = 'Bare' }) }
            { Get-ImperionAutotaskCompany } | Should -Not -Throw
            (Get-ImperionAutotaskCompany)[0].phone | Should -BeNullOrEmpty
        }
    }

    It 'queries the Companies entity with an incremental filter when -SinceDays is given' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @() }
            Get-ImperionAutotaskCompany -SinceDays 7 | Out-Null
            Should -Invoke Invoke-ImperionAutotaskRequest -Times 1 -ParameterFilter {
                $Entity -eq 'Companies' -and $Filter.field -eq 'lastActivityDate'
            }
        }
    }
}
