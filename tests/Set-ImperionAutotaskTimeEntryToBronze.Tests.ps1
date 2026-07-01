#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionAutotaskTimeEntryToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionAutotaskTimeEntryToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
        }
    }

    It 'upserts on external_ref with payload_bronze jsonb, no change-detect, app_user_id untouched' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert {
                $captured.Table = $Table; $captured.Rows = $Rows
                $captured.KeyColumns = $KeyColumns; $captured.JsonColumns = $JsonColumns
                $captured.NoChangeDetect = $NoChangeDetect
                [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 }
            }
            $row = [pscustomobject][ordered]@{
                external_ref = '5500'; autotask_resource_id = [long]42; autotask_ticket_id = [long]900
                work_date = [DateOnly]::Parse('2026-06-01'); started_at = [datetimeoffset]'2026-06-01T09:00:00Z'
                ended_at = [datetimeoffset]'2026-06-01T11:30:00Z'; hours_worked = [decimal]2.5
                payload_bronze = '{"id":5500}'; last_seen_at = [datetimeoffset]'2026-06-02T00:00:00Z'
                strayCollectorField = 'dropped-from-projection'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionAutotaskTimeEntryToBronze -Connection $conn

            $tally.inserted          | Should -Be 1
            $captured.Table          | Should -Be 'autotask_time_entry'
            $captured.KeyColumns     | Should -Be 'external_ref'
            $captured.JsonColumns    | Should -Be 'payload_bronze'
            $captured.NoChangeDetect | Should -BeTrue
            $captured.Rows[0].external_ref | Should -Be '5500'
            $captured.Rows[0].autotask_resource_id | Should -Be 42
            # Collector-owned columns only; merge-owned + stray fields are NOT projected.
            $projected = $captured.Rows[0].PSObject.Properties.Name
            $projected | Should -Not -Contain 'app_user_id'
            $projected | Should -Not -Contain 'matched_at'
            $projected | Should -Not -Contain 'strayCollectorField'
            $projected | Should -Contain 'last_seen_at'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionAutotaskTimeEntryToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ external_ref = '1'; payload_bronze = '{}'; last_seen_at = [datetimeoffset]::UtcNow }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionAutotaskTimeEntryToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
