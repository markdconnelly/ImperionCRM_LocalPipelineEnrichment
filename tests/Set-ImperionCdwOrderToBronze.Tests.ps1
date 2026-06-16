#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionCdwOrderToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionCdwOrderToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the cdw_orders column set and upserts on external_id (the order number)' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                order_id = 'CDW-555'; po_number = 'PO-42'; order_date = '2026-06-02'; order_status = 'Delivered'; order_total = '1899.00'; currency = 'USD'
                account_ref = 'ACCT-7'; tracking_number = '772233'; carrier = 'FedEx'; ship_status = 'Delivered'; estimated_delivery = '2026-06-04'
                tenant_id = 't1'; source = 'cdw'; external_id = 'CDW-555'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionCdwOrderToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'cdw_orders'
            $captured.Rows[0].external_id | Should -Be 'CDW-555'
            $captured.Rows[0].po_number | Should -Be 'PO-42'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionCdwOrderToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ order_total = '1'; tenant_id = 't'; source = 'cdw'; external_id = 'CDW-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionCdwOrderToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
