#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionPax8OrderToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionPax8OrderToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the pax8_orders column set and upserts on external_id' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                pax8_order_id = 'ORD-1'; company_id = 'CMP-1'; status = 'completed'; ordered_at = '2026-06-01'; total = '199.00'
                tenant_id = 't1'; source = 'pax8'; external_id = 'ORD-1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionPax8OrderToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'pax8_orders'
            $captured.Rows[0].total | Should -Be '199.00'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionPax8OrderToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
