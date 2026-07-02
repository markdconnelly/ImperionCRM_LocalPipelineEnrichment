#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionQboEstimateToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionQboEstimateToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the qbo_estimates column set and upserts on external_id (the estimate Id)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                doc_number = 'Q-200'; txn_date = '2026-05-20'; expiration_date = '2026-06-20'; txn_status = 'Accepted'; total_amount = '9000'
                customer_ref = 'C-1'; customer_name = 'Acme Co'; currency = 'USD'; created_time = 'c'; last_updated_time = 'm'
                tenant_id = 't1'; source = 'qbo'; external_id = 'EST-7'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionQboEstimateToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'qbo_estimates'
            $captured.Rows[0].external_id | Should -Be 'EST-7'
            $captured.Rows[0].txn_status | Should -Be 'Accepted'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionQboEstimateToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ total_amount = '1'; tenant_id = 't'; source = 'qbo'; external_id = 'EST-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionQboEstimateToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
