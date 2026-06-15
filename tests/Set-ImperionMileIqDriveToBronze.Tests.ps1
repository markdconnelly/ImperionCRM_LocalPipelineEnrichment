#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionMileIqDriveToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionMileIqDriveToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
        }
    }

    It 'upserts on mileiq_drive_id with payload_bronze jsonb, no change-detect, app_user_id projected' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert {
                $captured.Table = $Table; $captured.Rows = $Rows
                $captured.KeyColumns = $KeyColumns; $captured.JsonColumns = $JsonColumns
                $captured.NoChangeDetect = $NoChangeDetect
                [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 }
            }
            $row = [pscustomobject][ordered]@{
                mileiq_drive_id = 'DRV-100'; mileiq_user_id = 'mq-1'; app_user_id = 'user-7'
                drive_date = [DateOnly]::Parse('2026-06-03'); miles = [decimal]12.4
                origin = 'Office'; destination = 'Client Site'
                suggested_rate = [decimal]0.67; suggested_amount = [decimal]8.31
                payload_bronze = '{"id":"DRV-100"}'; last_seen_at = [datetimeoffset]'2026-06-04T00:00:00Z'
                strayCollectorField = 'dropped-from-projection'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionMileIqDriveToBronze -Connection $conn

            $tally.inserted          | Should -Be 1
            $captured.Table          | Should -Be 'mileiq_drive'
            $captured.KeyColumns     | Should -Be 'mileiq_drive_id'
            $captured.JsonColumns    | Should -Be 'payload_bronze'
            $captured.NoChangeDetect | Should -BeTrue
            $captured.Rows[0].mileiq_drive_id | Should -Be 'DRV-100'
            $captured.Rows[0].app_user_id     | Should -Be 'user-7'
            # Collector-owned columns only; merge-owned (matched_at) + stray fields are NOT projected.
            $projected = $captured.Rows[0].PSObject.Properties.Name
            $projected | Should -Contain 'app_user_id'
            $projected | Should -Contain 'suggested_amount'
            $projected | Should -Not -Contain 'matched_at'
            $projected | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionMileIqDriveToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ mileiq_drive_id = 'DRV-1'; payload_bronze = '{}'; last_seen_at = [datetimeoffset]::UtcNow }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionMileIqDriveToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
