#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionPostureSnapshot (issue #89, ADR-0011): DB calls are
# mocked in module scope; the fake Npgsql connection carries its TransactionLog on the
# object (via $this ScriptMethods) so the per-account transaction discipline is
# assertable — same pattern as Invoke-ImperionPostureMerge.Tests.ps1.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    $script:newFakeConnection = {
        $connection = [pscustomobject]@{ TransactionLog = [System.Collections.Generic.List[string]]::new() }
        $connection | Add-Member -MemberType ScriptMethod -Name BeginTransaction -Value {
            $tx = [pscustomobject]@{ Log = $this.TransactionLog }
            $tx | Add-Member -MemberType ScriptMethod -Name Commit -Value { $this.Log.Add('commit') }
            $tx | Add-Member -MemberType ScriptMethod -Name Rollback -Value { $this.Log.Add('rollback') }
            $tx | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $tx
        }
        $connection
    }
}

Describe 'Invoke-ImperionPostureSnapshot' {
    It 'is APPEND-ONLY: one snapshot INSERT + three pillar INSERTs, no UPDATE or DELETE ever' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:queries = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionDbQuery {
                $script:queries.Add($Sql)
                if ($Sql -match 'RETURNING id') { return @([pscustomobject]@{ id = [guid]::NewGuid() }) }
                @() # rollup read: no mapped-tenant rows
            }
            $script:pillarSql = [System.Collections.Generic.List[string]]::new()
            $script:pillarParams = [System.Collections.Generic.List[hashtable]]::new()
            Mock Invoke-ImperionDbNonQuery {
                $script:pillarSql.Add($Sql); $script:pillarParams.Add($Parameters); 1
            }

            $conn = & $makeConnection
            Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger on_demand -Connection $conn

            $insert = @($script:queries | Where-Object { $_ -match 'INSERT INTO posture_snapshot\b' })
            $insert.Count | Should -Be 1
            $insert[0] | Should -Match 'RETURNING id'

            $script:pillarSql.Count | Should -Be 3
            foreach ($sql in $script:pillarSql) {
                $sql | Should -Match 'INSERT INTO posture_snapshot_pillar'
                $sql | Should -Match '@metrics::jsonb'
            }
            # append-only by grant AND by code: nothing may UPDATE or DELETE snapshots
            foreach ($sql in @($script:queries) + @($script:pillarSql)) {
                $sql | Should -Not -Match '\b(UPDATE|DELETE)\b'
            }
            ($script:pillarParams.pillar | Sort-Object) | Should -Be @('darkweb', 'm365_secure_score', 'policy_compliance')

            $conn.TransactionLog | Should -Be @('commit')
        }
    }

    It 'reads rollups via LEFT JOIN from account_tenant so unmerged mapped tenants still count' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:rollupSql = $null
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'RETURNING id') { return @([pscustomobject]@{ id = [guid]::NewGuid() }) }
                if ($Sql -match 'FROM account_tenant m') { $script:rollupSql = $Sql }
                @()
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $conn = & $makeConnection
            Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger on_demand -Connection $conn

            $script:rollupSql | Should -Match 'LEFT JOIN tenant_posture tp'
            $script:rollupSql | Should -Match 'WHERE m\.account_id = @a::uuid'
        }
    }

    It 'gates scheduled runs to calendar quarters on the DB clock and skips snapshotted accounts' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:gateSql = $null
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'DISTINCT account_id FROM posture_snapshot') {
                    $script:gateSql = $Sql
                    return @([pscustomobject]@{ account_id = 'a-done' })
                }
                if ($Sql -match 'RETURNING id') { return @([pscustomobject]@{ id = [guid]::NewGuid() }) }
                @()
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $conn = & $makeConnection
            Invoke-ImperionPostureSnapshot -AccountId @('a-done', 'a-new') -Connection $conn

            # the gate is SQL date_trunc on now() — the DB clock, not this machine's
            $script:gateSql | Should -Match "date_trunc\('quarter', taken_at\) = date_trunc\('quarter', now\(\)\)"
            $script:gateSql | Should -Match "trigger = 'scheduled'"
            # a-done skipped, a-new snapshotted: exactly one committed transaction
            $conn.TransactionLog | Should -Be @('commit')
        }
    }

    It 'on_demand and business_review triggers bypass the quarter gate' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:gateQueried = $false
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'DISTINCT account_id FROM posture_snapshot') { $script:gateQueried = $true }
                if ($Sql -match 'RETURNING id') { return @([pscustomobject]@{ id = [guid]::NewGuid() }) }
                @()
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $conn = & $makeConnection
            Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger on_demand -Connection $conn
            Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger business_review `
                -BusinessReviewId 'br-1' -Connection $conn

            $script:gateQueried | Should -BeFalse
            $conn.TransactionLog | Should -Be @('commit', 'commit')
        }
    }

    It 'links the business review on business_review snapshots and enforces the pairing both ways' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:snapshotParams = $null
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'RETURNING id') {
                    $script:snapshotParams = $Parameters
                    return @([pscustomobject]@{ id = [guid]::NewGuid() })
                }
                @()
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $conn = & $makeConnection
            Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger business_review `
                -BusinessReviewId 'br-1' -Connection $conn
            $script:snapshotParams.br | Should -Be 'br-1'
            $script:snapshotParams.trigger | Should -Be 'business_review'

            # scheduled/on_demand rows carry NULL, never '' (''::uuid would throw)
            Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger on_demand -Connection $conn
            $script:snapshotParams.br | Should -BeNullOrEmpty

            { Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger business_review -Connection $conn } |
                Should -Throw '*requires -BusinessReviewId*'
            { Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger on_demand `
                    -BusinessReviewId 'br-1' -Connection $conn } |
                Should -Throw '*only valid with*'
        }
    }

    It 'stores the Score Model v1 result at capture (composite, grade, model version, pillar rows)' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:snapshotParams = $null
            $script:pillarParams = [System.Collections.Generic.List[hashtable]]::new()
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'RETURNING id') {
                    $script:snapshotParams = $Parameters
                    return @([pscustomobject]@{ id = [guid]::NewGuid() })
                }
                # one fully-reporting tenant: m365 = 90, policy = 90, darkweb = 90
                @([pscustomobject]@{
                        secure_score_current = 90; secure_score_max = 100; licensed_user_count = 10
                        policies_compliant = 90; policies_drift = 10; policies_ungoverned = 0
                        policies_missing = 0; exposures_open = 1; refreshed_at = '2026-06-11'
                    })
            }
            Mock Invoke-ImperionDbNonQuery { $script:pillarParams.Add($Parameters); 1 }

            $conn = & $makeConnection
            Invoke-ImperionPostureSnapshot -AccountId 'a-1' -Trigger on_demand -Connection $conn

            $script:snapshotParams.model | Should -Be 1
            $script:snapshotParams.composite | Should -Be 90
            $script:snapshotParams.grade | Should -Be 'A'
            $script:pillarParams.Count | Should -Be 3
            foreach ($p in $script:pillarParams) {
                $p.covered | Should -BeTrue
                $p.score | Should -Be 90
                $p.weight | Should -Be 1
                { $p.metrics | ConvertFrom-Json } | Should -Not -Throw
            }
        }
    }

    It 'rolls back a failing account and keeps snapshotting the rest of the fleet' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            $script:inserts = 0
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'RETURNING id') {
                    $script:inserts++
                    if ($script:inserts -eq 1) { throw 'account a-bad exploded' }
                    return @([pscustomobject]@{ id = [guid]::NewGuid() })
                }
                @()
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $conn = & $makeConnection
            { Invoke-ImperionPostureSnapshot -AccountId @('a-bad', 'a-good') -Trigger on_demand -Connection $conn } |
                Should -Not -Throw

            $conn.TransactionLog | Should -Be @('rollback', 'commit')
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Error' } -Times 1
        }
    }
}
