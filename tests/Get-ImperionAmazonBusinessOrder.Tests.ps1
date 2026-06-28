#Requires -Modules Pester
# Hermetic tests for Get-ImperionAmazonBusinessOrder: request + token resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAmazonBusinessOrder' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Resolve-ImperionAmazonBusinessToken { 'resolved-token' }
        }
    }

    It 'flattens orders to the bronze envelope (source amazon_business), external_id = orderId' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAmazonBusinessRequest {
                , @([pscustomobject]@{
                        orderId      = 'AB-100'
                        orderDate    = '2026-06-01'
                        orderStatus  = 'Shipped'
                        orderTotal   = [pscustomobject]@{ amount = '249.99'; currencyCode = 'USD' }
                        buyerInfo    = [pscustomobject]@{ name = 'Derek' }
                        shipment     = [pscustomobject]@{ trackingNumber = '1Z999'; carrier = 'UPS'; status = 'InTransit'; estimatedDeliveryDate = '2026-06-05' }
                    })
            }
            $rows = @(Get-ImperionAmazonBusinessOrder)
            $rows[0].order_id           | Should -Be 'AB-100'
            $rows[0].order_status       | Should -Be 'Shipped'
            $rows[0].order_total        | Should -Be '249.99'
            $rows[0].currency           | Should -Be 'USD'
            $rows[0].buyer_name         | Should -Be 'Derek'
            $rows[0].tracking_number    | Should -Be '1Z999'
            $rows[0].carrier            | Should -Be 'UPS'
            $rows[0].estimated_delivery | Should -Be '2026-06-05'
            $rows[0].source             | Should -Be 'amazon_business'
            $rows[0].tenant_id          | Should -Be 'partner'
            $rows[0].external_id        | Should -Be 'AB-100'
            $rows[0].content_hash       | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAmazonBusinessRequest { , @([pscustomobject]@{ orderId = 'AB-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionAmazonBusinessOrder)
            $rows[0].order_total  | Should -BeNullOrEmpty
            $rows[0].carrier      | Should -BeNullOrEmpty
            $rows[0].external_id  | Should -Be 'AB-9'
            $rows[0].raw_payload  | Should -Match 'surpriseField'
        }
    }

    It 'does not throw when shipment fields are absent (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAmazonBusinessRequest { , @([pscustomobject]@{ orderId = 'AB-bare' }) }
            { Get-ImperionAmazonBusinessOrder } | Should -Not -Throw
            (Get-ImperionAmazonBusinessOrder)[0].tracking_number | Should -BeNullOrEmpty
        }
    }

    It 'resolves the company token via Resolve-ImperionAmazonBusinessToken and passes it to the request' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAmazonBusinessRequest { , @() }
            Get-ImperionAmazonBusinessOrder | Out-Null
            Should -Invoke Resolve-ImperionAmazonBusinessToken -Times 1
            Should -Invoke Invoke-ImperionAmazonBusinessRequest -Times 1 -ParameterFilter { $AccessToken -eq 'resolved-token' }
        }
    }
}
