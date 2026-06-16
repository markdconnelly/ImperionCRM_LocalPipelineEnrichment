#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionSecurityRetentionSweep (issue #196, ADR-0019 §3).
# DB count + delete + logging mocked in module scope so the 180-day cutoff, the
# security-tables-ONLY scope, leaf-first ordering, count-only logging, WhatIf, and
# idempotency are all observable with no database and no network.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    $script:newFakeConnection = {
        $connection = [pscustomobject]@{}
        $connection | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $connection
    }
}

Describe 'Invoke-ImperionSecurityRetentionSweep' {
    It 'prunes the three m365_* security tables leaf-first and ONLY those tables' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ n = 5 }) }   # 5 eligible per table
            $script:deletedTables = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionDbNonQuery {
                if ($Sql -match 'DELETE FROM "(m365_[a-z]+)"') { $script:deletedTables.Add($Matches[1]) }
                5
            }

            $tally = Invoke-ImperionSecurityRetentionSweep -Connection (& $makeConnection) -Confirm:$false

            $tally.evidence  | Should -Be 5
            $tally.alerts    | Should -Be 5
            $tally.incidents | Should -Be 5
            # Leaf-first: evidence (children) before alerts before incidents (parents).
            $script:deletedTables[0] | Should -Be 'm365_evidence'
            $script:deletedTables[1] | Should -Be 'm365_alerts'
            $script:deletedTables[2] | Should -Be 'm365_incidents'
            # Scope guard: never touches interaction bronze or the purview posture tables.
            ($script:deletedTables -join ' ') | Should -Not -Match 'interaction'
            ($script:deletedTables -join ' ') | Should -Not -Match 'purview'
        }
    }

    It 'defaults the cutoff to 180 days and compares against collected_at' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:seenDays = [System.Collections.Generic.List[int]]::new()
            $script:seenSql = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionDbQuery {
                $script:seenSql.Add($Sql)
                if ($Parameters.ContainsKey('days')) { $script:seenDays.Add([int]$Parameters['days']) }
                @([pscustomobject]@{ n = 0 })
            }
            Mock Invoke-ImperionDbNonQuery { 0 }

            Invoke-ImperionSecurityRetentionSweep -Connection (& $makeConnection) -Confirm:$false | Out-Null

            $script:seenDays | Should -Contain 180
            ($script:seenSql -join ' ') | Should -Match '"collected_at" <'
        }
    }

    It 'WhatIf: counts eligible rows but deletes nothing' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ n = 7 }) }
            Mock Invoke-ImperionDbNonQuery { 7 }

            $tally = Invoke-ImperionSecurityRetentionSweep -Connection (& $makeConnection) -WhatIf

            $tally.evidence  | Should -Be 0
            $tally.incidents | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0   # no DELETE under WhatIf
        }
    }

    It 'is idempotent: zero eligible rows means no DELETE is issued' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ n = 0 }) }
            Mock Invoke-ImperionDbNonQuery { 0 }

            $tally = Invoke-ImperionSecurityRetentionSweep -Connection (& $makeConnection) -Confirm:$false

            $tally.evidence | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'scopes by tenant when -TenantId is given (per-tenant isolation)' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:seenTenant = $false
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'AND tenant_id = @t' -and $Parameters.ContainsKey('t') -and $Parameters['t'] -eq 'customer-9') { $script:seenTenant = $true }
                @([pscustomobject]@{ n = 0 })
            }
            Mock Invoke-ImperionDbNonQuery { 0 }

            Invoke-ImperionSecurityRetentionSweep -Connection (& $makeConnection) -TenantId 'customer-9' -Confirm:$false | Out-Null
            $script:seenTenant | Should -BeTrue
        }
    }
}
