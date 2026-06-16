#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionAmazonBusinessOrderToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionAmazonBusinessOrderToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the amazon_business_orders column set and upserts on external_id (the order id)' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                order_id = 'AB-100'; order_date = '2026-06-01'; order_status = 'Shipped'; order_total = '249.99'; currency = 'USD'
                buyer_name = 'Derek'; tracking_number = '1Z999'; carrier = 'UPS'; ship_status = 'InTransit'; estimated_delivery = '2026-06-05'
                tenant_id = 't1'; source = 'amazon_business'; external_id = 'AB-100'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionAmazonBusinessOrderToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'amazon_business_orders'
            $captured.Rows[0].external_id | Should -Be 'AB-100'
            $captured.Rows[0].order_total | Should -Be '249.99'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionAmazonBusinessOrderToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ order_total = '1'; tenant_id = 't'; source = 'amazon_business'; external_id = 'AB-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionAmazonBusinessOrderToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
