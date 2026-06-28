#Requires -Modules Pester
# Hermetic tests for Get-ImperionPax8License: Pax8 request + credential resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPax8License' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Resolve-ImperionPax8Credential { @{ ClientId = 'id'; ClientSecret = 'secret' } }
        }
    }

    It 'flattens a license to the pax8_licenses envelope (external_id = id)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request {
                , @([pscustomobject]@{
                        id = 'LIC-1'; subscriptionId = 'SUB-1'; companyId = 'CMP-1'; productId = 'PRD-9'
                        assignedTo = 'user@acme.com'; quantity = 1; status = 'assigned'
                    })
            }
            $rows = @(Get-ImperionPax8License)
            $rows[0].pax8_license_id | Should -Be 'LIC-1'
            $rows[0].subscription_id | Should -Be 'SUB-1'
            $rows[0].company_id      | Should -Be 'CMP-1'
            $rows[0].assigned_to     | Should -Be 'user@acme.com'
            $rows[0].status          | Should -Be 'assigned'
            $rows[0].source          | Should -Be 'pax8'
            $rows[0].external_id     | Should -Be 'LIC-1'
        }
    }

    It 'passes the resolved credential to /v1/licenses' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request { , @() }
            Get-ImperionPax8License | Out-Null
            Should -Invoke Invoke-ImperionPax8Request -Times 1 -ParameterFilter { $Path -eq '/v1/licenses' }
        }
    }
}
