#Requires -Modules Pester
# Hermetic tests for the Invoke-ImperionMergeByPlan scaffold (issue #430, epic #429,
# ADR-0026). DB calls are mocked in module scope; a fake Npgsql connection supplies
# BeginTransaction so the per-tenant transaction discipline (begin -> commit on success,
# rollback on failure, never block the fleet) is observable. The fake records its
# transaction lifecycle onto the connection's own TransactionLog (carried via $this) so
# it is scope-independent and assertable from inside InModuleScope.
#
# These tests ARE the point of the seam: they pin the orchestration invariants the 13
# Invoke-Imperion*Merge cmdlets will inherit once they become thin Plan-builders.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    # A fake connection whose BeginTransaction records 'begin' and returns a transaction
    # that records 'commit' / 'rollback' onto the connection's TransactionLog. Lets a test
    # assert both THAT a transaction was opened and how it ended (Global = empty log).
    $script:newFakeConnection = {
        $connection = [pscustomobject]@{ TransactionLog = [System.Collections.Generic.List[string]]::new() }
        $connection | Add-Member -MemberType ScriptMethod -Name BeginTransaction -Value {
            $this.TransactionLog.Add('begin')
            $tx = [pscustomobject]@{ Log = $this.TransactionLog }
            $tx | Add-Member -MemberType ScriptMethod -Name Commit   -Value { $this.Log.Add('commit') }
            $tx | Add-Member -MemberType ScriptMethod -Name Rollback -Value { $this.Log.Add('rollback') }
            $tx | Add-Member -MemberType ScriptMethod -Name Dispose  -Value { }
            $tx
        }
        $connection
    }
}

Describe 'Invoke-ImperionMergeByPlan' {

    Context 'Global scope' {
        It 'runs every step once, in order, without opening a transaction, and tallies rows by step name' {
            InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                $script:calls = [System.Collections.Generic.List[object]]::new()
                Mock Invoke-ImperionDbNonQuery {
                    $script:calls.Add([pscustomobject]@{ Sql = $Sql; Parameters = $Parameters })
                    if ($Sql -match 'one') { 3 } else { 5 }   # rows affected per step
                }

                $plan = @{
                    Source = 'widget'
                    Scope  = 'Global'
                    Steps  = @(
                        @{ Name = 'step_one'; Sql = 'INSERT INTO one SELECT 1' }
                        @{ Name = 'step_two'; Sql = 'INSERT INTO two SELECT 2' }
                    )
                }

                $conn = & $makeConnection
                $result = Invoke-ImperionMergeByPlan -Plan $plan -Connection $conn

                # one call per step, in declared order
                $script:calls.Count | Should -Be 2
                $script:calls[0].Sql | Should -Match 'INTO one'
                $script:calls[1].Sql | Should -Match 'INTO two'

                # Global never opens a transaction
                $conn.TransactionLog.Count | Should -Be 0

                # tally keyed by step Name = rows affected
                $result.tally['step_one'] | Should -Be 3
                $result.tally['step_two'] | Should -Be 5
            }
        }
    }

    Context 'PerTenant scope' {
        It 'wraps all steps for a tenant in one transaction, injects @t merged with step params, and tallies across tenants' {
            InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                $script:calls = [System.Collections.Generic.List[object]]::new()
                Mock Invoke-ImperionDbNonQuery {
                    # clone the params so later @t injection can't retro-mutate the record
                    $script:calls.Add([pscustomobject]@{ Sql = $Sql; Parameters = $Parameters.Clone() })
                    1
                }

                $sharedParams = @{ f = 'fam' }
                $plan = @{
                    Source = 'posture'
                    Scope  = 'PerTenant'
                    Steps  = @(
                        @{ Name = 'del';    Sql = 'DELETE FROM x WHERE tenant_id = @t' }
                        @{ Name = 'insert'; Sql = 'INSERT INTO x SELECT @t, @f'; Parameters = $sharedParams }
                    )
                }

                $conn = & $makeConnection
                $result = Invoke-ImperionMergeByPlan -Plan $plan -TenantId @('t-1', 't-2') -Connection $conn

                # 2 tenants x 2 steps = 4 writes
                $script:calls.Count | Should -Be 4

                # @t injected into EVERY step, set to the current tenant
                $script:calls[0].Parameters.t | Should -Be 't-1'   # del, t-1
                $script:calls[1].Parameters.t | Should -Be 't-1'   # insert, t-1
                $script:calls[2].Parameters.t | Should -Be 't-2'   # del, t-2
                $script:calls[3].Parameters.t | Should -Be 't-2'   # insert, t-2

                # @t merged WITH the step's own params (not replacing them)
                $script:calls[1].Parameters.f | Should -Be 'fam'
                $script:calls[3].Parameters.f | Should -Be 'fam'

                # the original Plan step params are NEVER mutated (no leaked @t)
                $sharedParams.ContainsKey('t') | Should -BeFalse

                # one begin+commit per tenant
                $conn.TransactionLog | Should -Be @('begin', 'commit', 'begin', 'commit')

                # tally sums rows across tenants; tenant counts reported
                $result.tally['del']    | Should -Be 2
                $result.tally['insert'] | Should -Be 2
                $result.tenantsMerged | Should -Be 2
                $result.tenantsFailed | Should -Be 0
            }
        }

        It 'rolls back a failing tenant, keeps merging the fleet, and excludes the rolled-back rows from the tally' {
            InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                Mock Invoke-ImperionDbNonQuery {
                    # tenant t-B explodes on its INSERT (after its DELETE already ran)
                    if ($Parameters.t -eq 't-B' -and $Sql -match 'INSERT') { throw 't-B exploded' }
                    1
                }

                $plan = @{
                    Source = 'posture'
                    Scope  = 'PerTenant'
                    Steps  = @(
                        @{ Name = 'del';    Sql = 'DELETE FROM x WHERE tenant_id = @t' }
                        @{ Name = 'insert'; Sql = 'INSERT INTO x SELECT @t' }
                    )
                }

                $conn = & $makeConnection
                $script:result = $null
                { $script:result = Invoke-ImperionMergeByPlan -Plan $plan -TenantId @('t-A', 't-B', 't-C') -Connection $conn } |
                    Should -Not -Throw

                # middle tenant rolled back; A and C committed
                $conn.TransactionLog | Should -Be @('begin', 'commit', 'begin', 'rollback', 'begin', 'commit')
                $script:result.tenantsMerged | Should -Be 2
                $script:result.tenantsFailed | Should -Be 1
                Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly

                # tally counts ONLY committed tenants: t-B's DELETE ran but was rolled
                # back, so it must not inflate the tally (accuracy invariant).
                $script:result.tally['del']    | Should -Be 2
                $script:result.tally['insert'] | Should -Be 2
            }
        }

        It 'enumerates tenants from TenantEnumerationSql when -TenantId is not supplied' {
            InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                Mock Invoke-ImperionDbNonQuery { 1 }
                $script:enumSql = $null
                Mock Invoke-ImperionDbQuery {
                    $script:enumSql = $Sql
                    @([pscustomobject]@{ tenant_id = 't-1' }, [pscustomobject]@{ tenant_id = 't-2' })
                }

                $plan = @{
                    Source               = 'posture'
                    Scope                = 'PerTenant'
                    TenantEnumerationSql = 'SELECT DISTINCT tenant_id FROM secure_scores'
                    Steps                = @(@{ Name = 'del'; Sql = 'DELETE FROM x WHERE tenant_id = @t' })
                }

                $conn = & $makeConnection
                $result = Invoke-ImperionMergeByPlan -Plan $plan -Connection $conn

                $script:enumSql | Should -Be 'SELECT DISTINCT tenant_id FROM secure_scores'
                # two enumerated tenants -> two committed transactions
                $conn.TransactionLog | Should -Be @('begin', 'commit', 'begin', 'commit')
                $result.tenantsMerged | Should -Be 2
            }
        }
    }

    Context 'ShouldProcess' {
        It 'PerTenant -WhatIf opens no transaction and issues no writes' {
            InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                Mock Invoke-ImperionDbNonQuery { 1 }

                $plan = @{
                    Source = 'posture'; Scope = 'PerTenant'
                    Steps  = @(@{ Name = 'del'; Sql = 'DELETE FROM x WHERE tenant_id = @t' })
                }

                $conn = & $makeConnection
                Invoke-ImperionMergeByPlan -Plan $plan -TenantId @('t-1', 't-2') -Connection $conn -WhatIf

                $conn.TransactionLog.Count | Should -Be 0
                Should -Invoke Invoke-ImperionDbNonQuery -Times 0 -Exactly
            }
        }

        It 'Global -WhatIf issues no writes' {
            InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                Mock Invoke-ImperionDbNonQuery { 1 }

                $plan = @{
                    Source = 'dns'; Scope = 'Global'
                    Steps  = @(@{ Name = 'upsert'; Sql = 'INSERT INTO dns_domain SELECT 1' })
                }

                $conn = & $makeConnection
                Invoke-ImperionMergeByPlan -Plan $plan -Connection $conn -WhatIf

                Should -Invoke Invoke-ImperionDbNonQuery -Times 0 -Exactly
            }
        }
    }

    Context 're-run convergence' {
        It 'emits identical writes on a second run and never mutates the Plan' {
            InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                $script:runs = [System.Collections.Generic.List[object]]::new()
                Mock Invoke-ImperionDbNonQuery {
                    $script:runs.Add([pscustomobject]@{ Sql = $Sql; T = $Parameters.t; F = $Parameters.f }); 1
                }

                $sharedParams = @{ f = 'fam' }
                $plan = @{
                    Source = 'posture'; Scope = 'PerTenant'
                    Steps  = @(@{ Name = 'insert'; Sql = 'INSERT INTO x SELECT @t, @f'; Parameters = $sharedParams })
                }

                $conn1 = & $makeConnection
                Invoke-ImperionMergeByPlan -Plan $plan -TenantId @('t-1', 't-2') -Connection $conn1
                $firstRun = $script:runs | ForEach-Object { "$($_.Sql)|$($_.T)|$($_.F)" }

                $script:runs.Clear()
                $conn2 = & $makeConnection
                Invoke-ImperionMergeByPlan -Plan $plan -TenantId @('t-1', 't-2') -Connection $conn2
                $secondRun = $script:runs | ForEach-Object { "$($_.Sql)|$($_.T)|$($_.F)" }

                # byte-identical emission across runs (no leaked @t, no drift)
                $secondRun | Should -Be $firstRun
                $secondRun | Should -Be @('INSERT INTO x SELECT @t, @f|t-1|fam', 'INSERT INTO x SELECT @t, @f|t-2|fam')
                # the Plan's own step params survive untouched
                $sharedParams.ContainsKey('t') | Should -BeFalse
                $sharedParams.f | Should -Be 'fam'
            }
        }
    }

    Context 'connection lifecycle' {
        It 'opens and disposes its own connection when none is supplied, but never disposes a reused one' {
            InModuleScope ImperionPipeline {
                Mock Write-ImperionLog { }
                Mock Invoke-ImperionDbNonQuery { 1 }

                # a fake connection that records Dispose()
                $newDisposable = {
                    $c = [pscustomobject]@{ Disposed = $false }
                    $c | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
                    $c
                }

                $owned = & $newDisposable
                Mock New-ImperionDbConnection { $owned }

                $plan = @{ Source = 'dns'; Scope = 'Global'; Steps = @(@{ Name = 'u'; Sql = 'INSERT INTO d SELECT 1' }) }

                # no -Connection: scaffold opens its own and disposes it
                Invoke-ImperionMergeByPlan -Plan $plan
                Should -Invoke New-ImperionDbConnection -Times 1 -Exactly
                $owned.Disposed | Should -BeTrue

                # -Connection supplied: caller owns it, scaffold must not dispose
                $reused = & $newDisposable
                Invoke-ImperionMergeByPlan -Plan $plan -Connection $reused
                $reused.Disposed | Should -BeFalse
            }
        }
    }
}
