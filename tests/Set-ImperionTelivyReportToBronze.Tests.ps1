#Requires -Modules Pester
# Hermetic test for Set-ImperionTelivyReportToBronze: verifies the ADR-0039 envelope remap.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionTelivyReportToBronze' {
    It 'projects standard-envelope rows to external_ref/payload_bronze and upserts with -NoChangeDetect' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; Keys = $KeyColumns; Json = $JsonColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{ external_id = 'r1'; raw_payload = '{"a":1}'; source = 'televy'; tenant_id = 't1'; title = 'T' }
            )
            $rows | Set-ImperionTelivyReportToBronze | Out-Null

            $script:captured.Table    | Should -Be 'televy_reports'
            $script:captured.Keys     | Should -Be 'external_ref'
            $script:captured.Json     | Should -Be 'payload_bronze'
            $script:captured.NoChange | Should -BeTrue
            $projected = $script:captured.Rows[0]
            $projected.external_ref   | Should -Be 'r1'
            $projected.payload_bronze | Should -Be '{"a":1}'
            # standard-envelope business columns are dropped — the table doesn't have them.
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be @('external_ref', 'payload_bronze' | Sort-Object)
        }
    }

    It 'writes nothing for empty input' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }
            (@() | Set-ImperionTelivyReportToBronze).scanned | Should -Be 0
        }
    }
}
