#Requires -Modules Pester
# Hermetic tests for Set-ImperionM365GroupMemberToBronze: standard envelope, projected to
# the exact m365_group_members column set (front-end migration 0079, issue #257 / #139).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionM365GroupMemberToBronze' {
    It 'projects rows to the exact 0079 m365_group_members column set and change-detect upserts' {
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
                    group_external_id = 'grp-1'; member_external_id = 'user-a'
                    member_type = '#microsoft.graph.user'; member_display_name = 'Ada Byron'
                    member_user_principal_name = 'ada@imperionllc.com'; member_mail = 'ada@imperionllc.com'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'grp-1/user-a'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionM365GroupMemberToBronze

            $script:captured.Table    | Should -Be 'm365_group_members'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'group_external_id', 'member_external_id', 'member_type',
                    'member_display_name', 'member_user_principal_name', 'member_mail',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.group_external_id  | Should -Be 'grp-1'
            $projected.member_external_id | Should -Be 'user-a'
            ($projected.PSObject.Properties.Name -contains 'future_extra') | Should -BeFalse  # dropped from flat projection
            $projected.external_id        | Should -Be 'grp-1/user-a'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionM365GroupMemberToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ group_external_id = 'g'; external_id = 'g/m'; content_hash = 'h' }
            { $row | Set-ImperionM365GroupMemberToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
