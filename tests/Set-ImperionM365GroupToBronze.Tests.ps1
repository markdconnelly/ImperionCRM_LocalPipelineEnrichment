#Requires -Modules Pester
# Hermetic tests for Set-ImperionM365GroupToBronze: standard envelope, projected to the
# exact m365_groups column set (front-end migration 0079, issue #257 / #150).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionM365GroupToBronze' {
    It 'projects rows to the exact 0079 m365_groups column set and change-detect upserts' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
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
                    display_name = 'Operations Team'; mail_nickname = 'ops'; mail = 'ops@imperionllc.com'
                    description = 'Ops staff'; group_types = 'Unified'
                    security_enabled = 'false'; mail_enabled = 'true'; visibility = 'Private'
                    classification = $null; is_assignable_to_role = 'false'
                    membership_rule = $null; membership_rule_processing_state = $null
                    on_premises_sync_enabled = $null
                    created_date_time = '2024-02-01T09:00:00Z'; renewed_date_time = '2026-05-01T09:00:00Z'
                    expiration_date_time = $null
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'grp-unified-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionM365GroupToBronze

            $script:captured.Table    | Should -Be 'm365_groups'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'display_name', 'mail_nickname', 'mail', 'description', 'group_types',
                    'security_enabled', 'mail_enabled', 'visibility', 'classification',
                    'is_assignable_to_role', 'membership_rule', 'membership_rule_processing_state',
                    'on_premises_sync_enabled', 'created_date_time', 'renewed_date_time',
                    'expiration_date_time',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.display_name   | Should -Be 'Operations Team'
            $projected.security_enabled | Should -Be 'false'
            ($projected.PSObject.Properties.Name -contains 'future_extra') | Should -BeFalse  # dropped from flat projection
            $projected.external_id    | Should -Be 'grp-unified-1'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionM365GroupToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ display_name = 'g'; external_id = 'grp'; content_hash = 'h' }
            { $row | Set-ImperionM365GroupToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
