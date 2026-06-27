#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionPax8Merge (issue #280): ShouldProcess gating, the keyed
# ON CONFLICT upsert into entity_xref, the manual-mapping guard, the exactly-one-name-match
# ambiguity rule, and one-bad-row isolation. The bronze→silver merge for Pax8 (ADR-0026), which
# records the pax8_company → account identity link in the golden-record registry (entity_xref,
# front-end 0160/0161, epic #1042).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionPax8Merge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
        }
    }

    It 'honors -WhatIf: no connection, no read, no write' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 0 }
            Invoke-ImperionPax8Merge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbQuery -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    It 'no bronze rows -> clean no-op (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 1 }
            $r = Invoke-ImperionPax8Merge -Confirm:$false
            $r.companies | Should -Be 0
            $r.resolved | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    Context 'merge contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                # Three companies: one unambiguous match (count 1), one ambiguous (count 2 -> skip),
                # one with no match (count 0 / null -> skip).
                Mock Invoke-ImperionDbQuery {
                    @(
                        [pscustomobject]@{ pax8_company_id = 'pc-1'; pax8_name = 'Acme Co';   account_id = 'acc-1'; match_count = 1 }
                        [pscustomobject]@{ pax8_company_id = 'pc-2'; pax8_name = 'Globex';     account_id = 'acc-2'; match_count = 2 }
                        [pscustomobject]@{ pax8_company_id = 'pc-3'; pax8_name = 'Unknown Ltd'; account_id = $null;  match_count = 0 }
                    )
                }
                $script:capturedSqls = [System.Collections.Generic.List[string]]::new()
                $script:capturedParams = [System.Collections.Generic.List[hashtable]]::new()
                # Two statement kinds now run: the entity_xref upsert (per company, with params)
                # and the set-based license_assignment upsert (#316, no params). Capture both.
                Mock Invoke-ImperionDbNonQuery {
                    $script:capturedSqls.Add($Sql)
                    if ($Parameters) { $script:capturedParams.Add($Parameters) }
                    1
                }
            }
        }

        It 'upserts ONLY the unambiguous (count=1) match and tallies the rest as unresolved' {
            InModuleScope ImperionPipeline {
                $r = Invoke-ImperionPax8Merge -Confirm:$false
                $r.companies | Should -Be 3
                $r.resolved | Should -Be 1
                $r.unresolved | Should -Be 2
                $r.failed | Should -Be 0
                $r.licenses | Should -Be 1
                # One entity_xref upsert (the lone count=1 company) + one license_assignment upsert.
                Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter { $Sql -match 'INSERT INTO entity_xref' }
                Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter { $Sql -match 'INSERT INTO license_assignment' }
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Pax8 merge complete' }
            }
        }

        It 'is a keyed ON CONFLICT upsert into entity_xref that protects manual links' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionPax8Merge -Confirm:$false | Out-Null
                $entitySql = $script:capturedSqls | Where-Object { $_ -match 'INSERT INTO entity_xref' } | Select-Object -First 1
                $entitySql | Should -Not -BeNullOrEmpty
                $entitySql | Should -Match "'account'"
                $entitySql | Should -Match "'pax8'"
                # entity_xref is SCD-2: the conflict target MUST repeat the partial live-row index
                # predicate (uq_entity_xref_source_live) or Postgres raises 42P10 (#403).
                $entitySql | Should -Match 'ON CONFLICT \(entity_type, source_system, source_key\) WHERE valid_to IS NULL AND system_to IS NULL DO UPDATE SET'
                # the human-curated mapping wins: DO UPDATE is guarded
                $entitySql | Should -Match "WHERE entity_xref.match_method <> 'manual'"
            }
        }

        It 'projects pax8_subscriptions into license_assignment, account-resolved + idempotent (#316)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionPax8Merge -Confirm:$false | Out-Null
                $licSql = $script:capturedSqls | Where-Object { $_ -match 'INSERT INTO license_assignment' } | Select-Object -First 1
                $licSql | Should -Not -BeNullOrEmpty
                $licSql | Should -Match 'FROM pax8_subscriptions'
                # account-resolved through the link the loop just wrote
                $licSql | Should -Match 'JOIN entity_xref'
                $licSql | Should -Match "source_system = 'pax8'"
                # idempotent on the distributor license grain
                $licSql | Should -Match 'ON CONFLICT \(source, external_ref\) DO UPDATE SET'
                # quantity is regex-guarded (bronze stores it as text), never a hard cast
                $licSql | Should -Match 'CASE WHEN btrim\(s.quantity\)'
            }
        }

        It 'binds the resolved account id and the Pax8 company id as the registry key' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionPax8Merge -Confirm:$false | Out-Null
                $p = $script:capturedParams | Where-Object { $_.source_key -eq 'pc-1' }
                $p | Should -Not -BeNullOrEmpty
                $p.internal_entity_id | Should -Be 'acc-1'
            }
        }

        It 'isolates one bad row: a throwing upsert is counted failed, not fatal' {
            InModuleScope ImperionPipeline {
                # Two unambiguous matches; the first upsert throws, the second succeeds.
                Mock Invoke-ImperionDbQuery {
                    @(
                        [pscustomobject]@{ pax8_company_id = 'pc-a'; pax8_name = 'A'; account_id = 'acc-a'; match_count = 1 }
                        [pscustomobject]@{ pax8_company_id = 'pc-b'; pax8_name = 'B'; account_id = 'acc-b'; match_count = 1 }
                    )
                }
                $script:calls = 0
                Mock Invoke-ImperionDbNonQuery {
                    $script:calls++
                    if ($script:calls -eq 1) { throw 'boom' }
                    1
                }
                $r = Invoke-ImperionPax8Merge -Confirm:$false
                $r.resolved | Should -Be 1
                $r.failed | Should -Be 1
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Error' -and $Message -match 'Pax8 merge failed' }
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionPax8Merge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}
