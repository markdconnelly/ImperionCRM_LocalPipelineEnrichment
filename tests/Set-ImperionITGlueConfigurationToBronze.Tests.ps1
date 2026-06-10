#Requires -Modules Pester
# Hermetic test for Set-ImperionITGlueConfigurationToBronze: verifies the ADR-0039 envelope remap into itglue_devices.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionITGlueConfigurationToBronze' {
    It 'projects standard-envelope rows to external_ref/payload_bronze and upserts itglue_devices with -NoChangeDetect' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            $script:opened = 0; $script:disposed = 0
            Mock New-ImperionDbConnection {
                $script:opened++
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; Keys = $KeyColumns; Json = $JsonColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{ external_id = 'g1'; raw_payload = '{"a":1}'; source = 'x'; tenant_id = 't1'; name = 'N'; content_hash = 'h' }
                [pscustomobject]@{ external_id = 'g12'; raw_payload = '{"a":2}'; source = 'x'; tenant_id = 't1'; name = 'M'; content_hash = 'i' }
            )
            $tally = $rows | Set-ImperionITGlueConfigurationToBronze

            $script:captured.Table    | Should -Be 'itglue_devices'
            $script:captured.Keys     | Should -Be 'external_ref'
            $script:captured.Json     | Should -Be 'payload_bronze'
            $script:captured.NoChange | Should -BeTrue
            @($script:captured.Rows).Count | Should -Be 2
            $projected = $script:captured.Rows[0]
            $projected.external_ref   | Should -Be 'g1'
            $projected.payload_bronze | Should -Be '{"a":1}'
            # standard-envelope business columns are dropped — the table doesn't have them.
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be @('external_ref', 'payload_bronze' | Sort-Object)
            $tally.scanned | Should -Be 2
            $script:opened | Should -Be 1      # opened its own connection...
            $script:disposed | Should -Be 1    # ...and disposed it
        }
    }

    It 'reuses a supplied connection and does not open or dispose one' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open its own connection' }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            $script:externalDisposed = 0
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:externalDisposed++ }
            $row = [pscustomobject]@{ external_id = 'g1'; raw_payload = '{}' }

            { $row | Set-ImperionITGlueConfigurationToBronze -Connection $conn } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 1
            $script:externalDisposed | Should -Be 0   # caller owns the connection
        }
    }

    It 'writes nothing and opens no connection for empty input' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }

            $tally = @() | Set-ImperionITGlueConfigurationToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honours -WhatIf: no upsert, no connection' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection under -WhatIf' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert under -WhatIf' }

            $row = [pscustomobject]@{ external_id = 'g1'; raw_payload = '{}' }
            { $row | Set-ImperionITGlueConfigurationToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
