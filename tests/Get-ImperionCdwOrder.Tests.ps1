#Requires -Modules Pester
# Hermetic tests for Get-ImperionCdwOrder: request + key resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionCdwOrder' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Resolve-ImperionCdwApiKey { 'resolved-key' }
        }
    }

    It 'flattens orders to the bronze envelope (source cdw), external_id = orderNumber' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionCdwRequest {
                , @([pscustomobject]@{
                        orderNumber = 'CDW-555'
                        poNumber    = 'PO-42'
                        orderDate   = '2026-06-02'
                        orderStatus = 'Delivered'
                        orderTotal  = [pscustomobject]@{ amount = '1899.00'; currencyCode = 'USD' }
                        accountId   = 'ACCT-7'
                        shipment    = [pscustomobject]@{ trackingNumber = '772233'; carrier = 'FedEx'; status = 'Delivered'; estimatedDeliveryDate = '2026-06-04' }
                    })
            }
            $rows = @(Get-ImperionCdwOrder)
            $rows[0].order_id           | Should -Be 'CDW-555'
            $rows[0].po_number          | Should -Be 'PO-42'
            $rows[0].order_status       | Should -Be 'Delivered'
            $rows[0].order_total        | Should -Be '1899.00'
            $rows[0].currency           | Should -Be 'USD'
            $rows[0].account_ref        | Should -Be 'ACCT-7'
            $rows[0].tracking_number    | Should -Be '772233'
            $rows[0].carrier            | Should -Be 'FedEx'
            $rows[0].estimated_delivery | Should -Be '2026-06-04'
            $rows[0].source             | Should -Be 'cdw'
            $rows[0].tenant_id          | Should -Be 'partner'
            $rows[0].external_id        | Should -Be 'CDW-555'
            $rows[0].content_hash       | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionCdwRequest { , @([pscustomobject]@{ orderNumber = 'CDW-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionCdwOrder)
            $rows[0].order_total | Should -BeNullOrEmpty
            $rows[0].po_number   | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'CDW-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'does not throw when shipment fields are absent (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionCdwRequest { , @([pscustomobject]@{ orderNumber = 'CDW-bare' }) }
            { Get-ImperionCdwOrder } | Should -Not -Throw
            (Get-ImperionCdwOrder)[0].tracking_number | Should -BeNullOrEmpty
        }
    }

    It 'resolves the company key via Resolve-ImperionCdwApiKey and passes it to the request' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionCdwRequest { , @() }
            Get-ImperionCdwOrder | Out-Null
            Should -Invoke Resolve-ImperionCdwApiKey -Times 1
            Should -Invoke Invoke-ImperionCdwRequest -Times 1 -ParameterFilter { $ApiKey -eq 'resolved-key' }
        }
    }
}
