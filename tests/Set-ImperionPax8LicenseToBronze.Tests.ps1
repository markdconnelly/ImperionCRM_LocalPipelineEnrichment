#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionPax8LicenseToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionPax8LicenseToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the pax8_licenses column set and upserts on external_id' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                pax8_license_id = 'LIC-1'; subscription_id = 'SUB-1'; company_id = 'CMP-1'; product_id = 'PRD-9'
                assigned_to = 'user@acme.com'; quantity = '1'; status = 'assigned'
                tenant_id = 't1'; source = 'pax8'; external_id = 'LIC-1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionPax8LicenseToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'pax8_licenses'
            $captured.Rows[0].assigned_to | Should -Be 'user@acme.com'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionPax8LicenseToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
