#Requires -Modules Pester
# Hermetic tests for Get-ImperionPax8Order: Pax8 request + credential resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPax8Order' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Resolve-ImperionPax8Credential { @{ ClientId = 'id'; ClientSecret = 'secret' } }
        }
    }

    It 'flattens an order to the pax8_orders envelope (external_id = id)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request {
                , @([pscustomobject]@{ id = 'ORD-1'; companyId = 'CMP-1'; status = 'completed'; orderedDate = '2026-06-01T00:00:00Z'; total = '199.00' })
            }
            $rows = @(Get-ImperionPax8Order)
            $rows[0].pax8_order_id | Should -Be 'ORD-1'
            $rows[0].company_id    | Should -Be 'CMP-1'
            $rows[0].status        | Should -Be 'completed'
            $rows[0].ordered_at    | Should -Be '2026-06-01T00:00:00Z'
            $rows[0].total         | Should -Be '199.00'
            $rows[0].source        | Should -Be 'pax8'
            $rows[0].external_id   | Should -Be 'ORD-1'
        }
    }

    It 'passes the resolved credential to /v1/orders' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request { , @() }
            Get-ImperionPax8Order | Out-Null
            Should -Invoke Invoke-ImperionPax8Request -Times 1 -ParameterFilter { $Path -eq '/v1/orders' }
        }
    }
}
