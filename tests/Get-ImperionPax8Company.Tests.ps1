#Requires -Modules Pester
# Hermetic tests for Get-ImperionPax8Company: Pax8 request + credential resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPax8Company' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Resolve-ImperionPax8Credential { @{ ClientId = 'id'; ClientSecret = 'secret' } }
        }
    }

    It 'flattens a company to the pax8_companies envelope (source pax8, external_id = id)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request {
                , @([pscustomobject]@{ id = 'CMP-1'; name = 'Acme Inc'; status = 'active' })
            }
            $rows = @(Get-ImperionPax8Company)
            $rows.Count | Should -Be 1
            $rows[0].pax8_company_id | Should -Be 'CMP-1'
            $rows[0].name            | Should -Be 'Acme Inc'
            $rows[0].status          | Should -Be 'active'
            $rows[0].source          | Should -Be 'pax8'
            $rows[0].tenant_id       | Should -Be 'partner'
            $rows[0].external_id     | Should -Be 'CMP-1'
            $rows[0].content_hash    | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request { , @([pscustomobject]@{ id = 'CMP-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionPax8Company)
            $rows[0].name        | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'CMP-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'resolves the MSP-wide credential and passes it to the connect layer for /v1/companies' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request { , @() }
            Get-ImperionPax8Company | Out-Null
            Should -Invoke Resolve-ImperionPax8Credential -Times 1
            Should -Invoke Invoke-ImperionPax8Request -Times 1 -ParameterFilter {
                $ClientId -eq 'id' -and $ClientSecret -eq 'secret' -and $Path -eq '/v1/companies'
            }
        }
    }
}
