#Requires -Modules Pester
# Hermetic test for Set-ImperionDarkWebIdCompromiseToBronze: verifies the ADR-0039 envelope remap.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionDarkWebIdCompromiseToBronze' {
    It 'projects rows to external_ref/payload_bronze and upserts darkwebid_exposures with -NoChangeDetect' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; Keys = $KeyColumns; Json = $JsonColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @([pscustomobject]@{ external_id = 'c1'; raw_payload = '{"email":"x"}'; source = 'darkwebid'; tenant_id = 't1'; email = 'x' })
            $rows | Set-ImperionDarkWebIdCompromiseToBronze | Out-Null

            $script:captured.Table    | Should -Be 'darkwebid_exposures'
            $script:captured.Keys     | Should -Be 'external_ref'
            $script:captured.Json     | Should -Be 'payload_bronze'
            $script:captured.NoChange | Should -BeTrue
            $script:captured.Rows[0].external_ref   | Should -Be 'c1'
            $script:captured.Rows[0].payload_bronze | Should -Be '{"email":"x"}'
        }
    }

    It 'writes nothing for empty input' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }
            (@() | Set-ImperionDarkWebIdCompromiseToBronze).scanned | Should -Be 0
        }
    }
}
