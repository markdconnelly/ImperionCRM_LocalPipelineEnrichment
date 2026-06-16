#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionQboPurchaseToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionQboPurchaseToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
        }
    }

    It 'projects rows to the qbo_purchases column set and upserts on external_id (the purchase Id)' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                txn_date = '2026-06-05'; total_amount = '1480.5'; payment_type = 'Check'; account_ref = 'A-1'; account_name = 'Operating Checking'
                entity_id = 'V-9'; entity_type = 'Vendor'; entity_name = 'Contractor LLC'; doc_number = 'CHK-1001'; currency = 'USD'
                created_time = 'c'; last_updated_time = 'm'
                tenant_id = 't1'; source = 'qbo'; external_id = 'PUR-77'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionQboPurchaseToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'qbo_purchases'
            $captured.Rows[0].external_id | Should -Be 'PUR-77'
            $captured.Rows[0].entity_id | Should -Be 'V-9'
            $captured.Rows[0].account_ref | Should -Be 'A-1'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionQboPurchaseToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ total_amount = '1'; tenant_id = 't'; source = 'qbo'; external_id = 'PUR-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionQboPurchaseToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
