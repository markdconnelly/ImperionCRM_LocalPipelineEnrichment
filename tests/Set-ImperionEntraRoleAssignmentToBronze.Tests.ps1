#Requires -Modules Pester
# Hermetic tests for Set-ImperionEntraRoleAssignmentToBronze: standard envelope, projected
# to the exact entra_role_assignments column set (front-end migration 0136 / #260; local #219/#142).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionEntraRoleAssignmentToBronze' {
    It 'projects rows to the exact entra_role_assignments column set and change-detect upserts' {
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
                    role_definition_id = 'role-ga'; role_display_name = 'Global Administrator'
                    is_privileged = 'true'
                    principal_id = 'user-mark'; principal_type = 'user'; principal_display_name = 'Mark Connelly'
                    directory_scope_id = '/'; assignment_type = 'Assigned'
                    principal_upn = 'mark@imperionllc.com'   # not a 0136 column — should be dropped
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'assignment-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionEntraRoleAssignmentToBronze

            $script:captured.Table    | Should -Be 'entra_role_assignments'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'role_definition_id', 'role_display_name', 'is_privileged',
                    'principal_id', 'principal_type', 'principal_display_name',
                    'directory_scope_id', 'assignment_type',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            ($projected.PSObject.Properties.Name -contains 'principal_upn') | Should -BeFalse
            ($projected.PSObject.Properties.Name -contains 'future_extra') | Should -BeFalse
            $projected.role_display_name | Should -Be 'Global Administrator'
            $projected.is_privileged     | Should -Be 'true'
            $projected.principal_type    | Should -Be 'user'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionEntraRoleAssignmentToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ role_display_name = 'r'; external_id = 'asn'; content_hash = 'h' }
            { $row | Set-ImperionEntraRoleAssignmentToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
