#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionQboProfitAndLossToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionQboProfitAndLossToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects the snapshot to the qbo_profit_and_loss column set and upserts on external_id (the period)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                period = '2026-06-01..2026-06-30'; start_date = '2026-06-01'; end_date = '2026-06-30'; report_period = 'ProfitAndLoss'; currency = 'USD'
                total_income = '20000.00'; total_expenses = '12000.00'; net_income = '8000.00'; generated_time = 'g'
                tenant_id = 't1'; source = 'qbo'; external_id = '2026-06-01..2026-06-30'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionQboProfitAndLossToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'qbo_profit_and_loss'
            $captured.Rows[0].external_id | Should -Be '2026-06-01..2026-06-30'
            $captured.Rows[0].net_income | Should -Be '8000.00'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionQboProfitAndLossToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ period = 'p'; tenant_id = 't'; source = 'qbo'; external_id = 'p'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionQboProfitAndLossToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
