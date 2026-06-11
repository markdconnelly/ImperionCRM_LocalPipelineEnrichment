#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionPostureMerge (issue #88, ADR-0010): DB calls are
# mocked in module scope; a fake Npgsql connection supplies BeginTransaction so the
# per-tenant transaction discipline (commit on success, rollback on failure, never
# block the fleet) is observable. The fake is built INSIDE InModuleScope so its
# ScriptMethod closures and the assertions share the module's script scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    # Returns a fake connection whose transactions record commit/rollback onto the
    # connection's own TransactionLog — carried on the object (via $this), so it is
    # scope-independent and assertable from inside InModuleScope.
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

Describe 'Invoke-ImperionPostureMerge' {
    It 'classifies all five families per tenant with the parity-pinned CASE, after a delete' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbQuery { @() }
            $script:capturedSql = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionDbNonQuery { $script:capturedSql.Add($Sql); 1 }

            $conn = & $makeConnection
            Invoke-ImperionPostureMerge -TenantId 't-1' -Connection $conn

            # delete + 5 family inserts + 1 rollup = 7 non-queries
            $script:capturedSql.Count | Should -Be 7
            $script:capturedSql[0] | Should -Match 'DELETE FROM posture_policy'

            $inserts = @($script:capturedSql | Where-Object { $_ -match 'INSERT INTO posture_policy' })
            $inserts.Count | Should -Be 5
            foreach ($sql in $inserts) {
                # PARITY PIN — this CASE must stay byte-equivalent to
                # Get-ImperionPolicyDrift and the cloud pipeline's posture-run.ts.
                $sql | Should -Match "WHEN g\.policy_id   IS NULL THEN 'ungoverned'"
                $sql | Should -Match "WHEN o\.external_id IS NULL THEN 'missing'"
                $sql | Should -Match "WHEN o\.content_hash = g\.golden_hash THEN 'compliant'"
                $sql | Should -Match "ELSE 'drift'"
                $sql | Should -Match 'FULL OUTER JOIN'
                # all-text bronze date guarded by the ISO-prefix regex
                $sql.Contains("~ '^\d{4}-\d{2}-\d{2}'") | Should -BeTrue
            }

            # one transaction per tenant, committed
            $conn.TransactionLog | Should -Be @('commit')
        }
    }

    It 'rolls up tenant_posture with guarded casts and exposures resolved through account_tenant' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbQuery { @() }
            $script:capturedSql = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionDbNonQuery { $script:capturedSql.Add($Sql); 1 }

            $conn = & $makeConnection
            Invoke-ImperionPostureMerge -TenantId 't-1' -Connection $conn

            $rollup = @($script:capturedSql | Where-Object { $_ -match 'INSERT INTO tenant_posture' })
            $rollup.Count | Should -Be 1
            $rollup[0] | Should -Match 'JOIN account_tenant m ON m\.account_id = e\.account_id'
            $rollup[0] | Should -Match "e\.status <> 'resolved'"
            $rollup[0] | Should -Match 'ON CONFLICT \(tenant_id\) DO UPDATE'
            # numeric casts are regex-guarded (bronze is all-text)
            $rollup[0].Contains("~ '^-?\d+(\.\d+)?$'") | Should -BeTrue
            $rollup[0] | Should -Match 'ORDER BY collected_at DESC LIMIT 1'
        }
    }

    It 'enumerates tenants from observed + golden + secure_scores when none are passed' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbNonQuery { 1 }
            $script:tenantSql = $null
            Mock Invoke-ImperionDbQuery {
                $script:tenantSql = $Sql
                @([pscustomobject]@{ tenant_id = 't-1' }, [pscustomobject]@{ tenant_id = 't-2' })
            }

            $conn = & $makeConnection
            Invoke-ImperionPostureMerge -Connection $conn

            foreach ($table in @(
                    'entra_conditional_access_policies', 'conditional_access_policies_golden',
                    'intune_security_policies', 'intune_security_policies_golden',
                    'device_configuration_policies', 'device_configuration_policies_golden',
                    'autopilot_policies', 'autopilot_policies_golden',
                    'defender_xdr_security_policies', 'defender_xdr_security_policies_golden',
                    'secure_scores')) {
                $script:tenantSql | Should -Match $table
            }
            # two tenants -> two committed transactions
            $conn.TransactionLog | Should -Be @('commit', 'commit')
        }
    }

    It 'stamps the underscore policy_family keys the silver CHECK constraint expects' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbQuery { @() }
            $script:families = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionDbNonQuery {
                if ($Parameters.ContainsKey('f')) { $script:families.Add($Parameters.f) }
                1
            }

            $conn = & $makeConnection
            Invoke-ImperionPostureMerge -TenantId 't-1' -Connection $conn

            ($script:families | Sort-Object) | Should -Be @(
                'autopilot', 'conditional_access', 'defender_xdr',
                'device_configuration', 'intune_security')
        }
    }

    It 'rolls back a failing tenant and keeps merging the rest of the fleet' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbQuery { @() }
            $script:deletes = 0
            Mock Invoke-ImperionDbNonQuery {
                if ($Sql -match 'DELETE FROM posture_policy') {
                    $script:deletes++
                    if ($script:deletes -eq 1) { throw 'tenant t-bad exploded' }
                }
                1
            }

            $conn = & $makeConnection
            { Invoke-ImperionPostureMerge -TenantId @('t-bad', 't-good') -Connection $conn } |
                Should -Not -Throw

            # first tenant rolled back, second committed
            $conn.TransactionLog | Should -Be @('rollback', 'commit')
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Error' } -Times 1
        }
    }
}
