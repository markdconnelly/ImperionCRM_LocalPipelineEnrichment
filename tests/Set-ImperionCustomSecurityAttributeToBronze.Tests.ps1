#Requires -Modules Pester
# Hermetic tests for Set-ImperionCustomSecurityAttributeToBronze: standard envelope, projected
# to the exact custom_security_attribute_definitions column set (ImperionCRM#259; local #141).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionCustomSecurityAttributeToBronze' {
    It 'projects rows to the exact custom_security_attribute_definitions column set and upserts' {
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
                    attribute_set = 'Engineering'; attribute_name = 'Project'; description = 'd'
                    type = 'String'; status = 'Available'; is_collection = 'true'; is_searchable = 'true'
                    use_predefined_values_only = 'true'; allowed_values = 'Alpha; Beta'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'Engineering_Project'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionCustomSecurityAttributeToBronze

            $script:captured.Table    | Should -Be 'custom_security_attribute_definitions'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'attribute_set', 'attribute_name', 'description', 'type', 'status',
                    'is_collection', 'is_searchable', 'use_predefined_values_only', 'allowed_values',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            ($projected.PSObject.Properties.Name -contains 'future_extra') | Should -BeFalse
            $projected.external_id | Should -Be 'Engineering_Project'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionCustomSecurityAttributeToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ attribute_set = 'S'; external_id = 'S_A'; content_hash = 'h' }
            { $row | Set-ImperionCustomSecurityAttributeToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
