#Requires -Modules Pester
# Hermetic tests for Get-ImperionPax8Subscription: Pax8 request + credential resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPax8Subscription' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Resolve-ImperionPax8Credential { @{ ClientId = 'id'; ClientSecret = 'secret' } }
        }
    }

    It 'flattens a subscription to the pax8_subscriptions envelope (external_id = id)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request {
                , @([pscustomobject]@{
                        id = 'SUB-1'; companyId = 'CMP-1'; productId = 'PRD-9'; productName = 'M365 BP'
                        quantity = 25; status = 'active'; billingTerm = 'monthly'; startDate = '2026-01-01T00:00:00Z'
                    })
            }
            $rows = @(Get-ImperionPax8Subscription)
            $rows[0].pax8_subscription_id | Should -Be 'SUB-1'
            $rows[0].company_id           | Should -Be 'CMP-1'
            $rows[0].product_id           | Should -Be 'PRD-9'
            $rows[0].product_name         | Should -Be 'M365 BP'
            $rows[0].quantity             | Should -Be '25'
            $rows[0].billing_term         | Should -Be 'monthly'
            $rows[0].source               | Should -Be 'pax8'
            $rows[0].external_id          | Should -Be 'SUB-1'
        }
    }

    It 'passes the resolved credential to /v1/subscriptions' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPax8Request { , @() }
            Get-ImperionPax8Subscription | Out-Null
            Should -Invoke Invoke-ImperionPax8Request -Times 1 -ParameterFilter { $Path -eq '/v1/subscriptions' }
        }
    }
}
