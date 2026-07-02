#Requires -Modules Pester
# Hermetic tests for Set-ImperionSentinelToBronze: multi-table router over the sentinel_*
# bronze set (migration 0038). DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionSentinelToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            $script:upserts = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-ImperionBronzeUpsert {
                $script:upserts.Add(@{ Table = $Table; Rows = $Rows })
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }
        }
    }

    It 'routes a mixed batch by entity, projecting each table''s exact column set (entity stripped)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $rows = @(
                [pscustomobject]@{
                    entity = 'analytic_rules'; name = 'ar-1'; display_name = 'Brute force'; rule_kind = 'Scheduled'
                    enabled = 'True'; severity = 'High'; tactics = 'CredentialAccess'; last_modified = '2026-06-01'; workspace = 'ws-sec'
                    tenant_id = 't1'; source = 'sentinel'; external_id = 'ar-1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
                [pscustomobject]@{
                    entity = 'workbooks'; display_name = 'Sentinel ops'; category = 'sentinel'; version = '1.0'
                    time_modified = '2026-06-03'; subscription_id = 'sub-1'
                    tenant_id = 't1'; source = 'sentinel'; external_id = 'wb-1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h2'
                }
            )
            $tally = $rows | Set-ImperionSentinelToBronze

            $tally.scanned | Should -Be 2
            $script:upserts.Count | Should -Be 2
            ($script:upserts.Table | Sort-Object) | Should -Be @('sentinel_analytic_rules', 'sentinel_workbooks')

            $ruleUpsert = $script:upserts | Where-Object { $_.Table -eq 'sentinel_analytic_rules' }
            ($ruleUpsert.Rows[0].PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'name', 'display_name', 'rule_kind', 'enabled', 'severity', 'tactics', 'last_modified', 'workspace',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)

            $workbookUpsert = $script:upserts | Where-Object { $_.Table -eq 'sentinel_workbooks' }
            ($workbookUpsert.Rows[0].PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'display_name', 'category', 'version', 'time_modified', 'subscription_id',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
        }
    }

    It 'uses -Entity for rows without a discriminator' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $row = [pscustomobject]@{ display_name = 'VIPs'; provider = 'Imperion'; external_id = 'wl-1'; content_hash = 'h' }
            $tally = $row | Set-ImperionSentinelToBronze -Entity watchlists
            $tally.scanned | Should -Be 1
            $script:upserts[0].Table | Should -Be 'sentinel_watchlists'
        }
    }

    It 'fails loudly on an unknown entity (never invents a table)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $row = [pscustomobject]@{ entity = 'incidents'; external_id = 'x' }
            { $row | Set-ImperionSentinelToBronze } | Should -Throw "*unknown Sentinel entity 'incidents'*"
        }
    }

    It 'throws when a row has no entity and no -Entity was supplied' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $row = [pscustomobject]@{ external_id = 'x' }
            { $row | Set-ImperionSentinelToBronze } | Should -Throw "*no 'entity' property*"
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            (@() | Set-ImperionSentinelToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ entity = 'workbooks'; external_id = 'wb'; content_hash = 'h' }
            ($row | Set-ImperionSentinelToBronze -WhatIf).inserted | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
