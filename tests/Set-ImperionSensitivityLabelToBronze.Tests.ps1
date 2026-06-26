#Requires -Modules Pester
# Hermetic tests for Set-ImperionSensitivityLabelToBronze: standard envelope, projected to the
# exact m365_sensitivity_labels column set (applied front-end ImperionCRM#575; local issue #141).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionSensitivityLabelToBronze' {
    It 'projects rows to the exact m365_sensitivity_labels column set and change-detect upserts' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{
                    label_id = 'label-conf'; name = 'Confidential'; priority = '2'; is_active = 'true'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'label-conf'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionSensitivityLabelToBronze

            $script:captured.Table    | Should -Be 'm365_sensitivity_labels'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'label_id', 'name', 'priority', 'is_active',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            ($projected.PSObject.Properties.Name -contains 'future_extra') | Should -BeFalse
            $projected.external_id | Should -Be 'label-conf'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionSensitivityLabelToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ label_id = 'label-pub'; name = 'Public'; external_id = 'label-pub'; content_hash = 'h' }
            { $row | Set-ImperionSensitivityLabelToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
