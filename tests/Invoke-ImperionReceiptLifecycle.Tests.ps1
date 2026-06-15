#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionReceiptLifecycle (issue #169, front-end ADR-0083).
# Every DB call, the blob delete, and logging are mocked in module scope so the
# verified-in-Autotask GUARD, the 90-day cutoff, idempotency, WhatIf, and the
# flag-don't-delete behaviour for unverified receipts are all observable with no
# database, no storage account, and no network.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    # A fake connection that Dispose()s cleanly (the cmdlet opens its own when -Connection
    # is omitted; here we pass one so New-ImperionDbConnection is never reached).
    $script:newFakeConnection = {
        $connection = [pscustomobject]@{}
        $connection | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $connection
    }
}

Describe 'Invoke-ImperionReceiptLifecycle' {
    It 'deletes the blob and stamps blob_deleted_at for a verified, aged receipt' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Remove-ImperionStorageBlob { $true }
            # Eligible cutoff query -> one verified row; flagged count -> 0; per-row re-verify -> verified.
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'count\(\*\) AS n') { return @([pscustomobject]@{ n = 0 }) }
                if ($Sql -match 'verified_in_autotask, blob_deleted_at') { return @([pscustomobject]@{ verified_in_autotask = $true; blob_deleted_at = $null }) }
                return @([pscustomobject]@{ id = 'r1'; blob_path = 'receipts/2026/01/a.pdf' })
            }
            $script:nonQuerySql = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionDbNonQuery { $script:nonQuerySql.Add($Sql); 1 }

            $tally = Invoke-ImperionReceiptLifecycle -Connection (& $makeConnection) -Confirm:$false

            $tally.deleted | Should -Be 1
            $tally.alreadyGone | Should -Be 0
            $tally.flaggedUnverified | Should -Be 0
            $tally.failed | Should -Be 0
            Should -Invoke Remove-ImperionStorageBlob -Times 1
            ($script:nonQuerySql -join ' ') | Should -Match 'UPDATE receipt_attachment SET blob_deleted_at = now\(\)'
        }
    }

    It 'GUARD: never deletes or stamps an unverified receipt - only flags it' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Remove-ImperionStorageBlob { $true }
            # The cutoff query (verified-only) returns nothing; the flagged-count query returns 3.
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'count\(\*\) AS n') { return @([pscustomobject]@{ n = 3 }) }
                return @()
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $tally = Invoke-ImperionReceiptLifecycle -Connection (& $makeConnection)

            $tally.flaggedUnverified | Should -Be 3
            $tally.deleted | Should -Be 0
            Should -Invoke Remove-ImperionStorageBlob -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0   # no blob_deleted_at stamp on unverified
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }

    It 'GUARD (defence in depth): skips a row whose per-row re-verify is no longer verified' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Remove-ImperionStorageBlob { $true }
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'count\(\*\) AS n') { return @([pscustomobject]@{ n = 0 }) }
                if ($Sql -match 'verified_in_autotask, blob_deleted_at') { return @([pscustomobject]@{ verified_in_autotask = $false; blob_deleted_at = $null }) }
                return @([pscustomobject]@{ id = 'r1'; blob_path = 'receipts/x.pdf' })
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $tally = Invoke-ImperionReceiptLifecycle -Connection (& $makeConnection)

            $tally.deleted | Should -Be 0
            Should -Invoke Remove-ImperionStorageBlob -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'is idempotent: an already-absent blob still stamps blob_deleted_at and counts as alreadyGone' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Remove-ImperionStorageBlob { $false }   # 404 / already gone
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'count\(\*\) AS n') { return @([pscustomobject]@{ n = 0 }) }
                if ($Sql -match 'verified_in_autotask, blob_deleted_at') { return @([pscustomobject]@{ verified_in_autotask = $true; blob_deleted_at = $null }) }
                return @([pscustomobject]@{ id = 'r1'; blob_path = 'receipts/x.pdf' })
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $tally = Invoke-ImperionReceiptLifecycle -Connection (& $makeConnection) -Confirm:$false

            $tally.alreadyGone | Should -Be 1
            $tally.deleted | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1   # the stamp still runs -> converges
        }
    }

    It 'WhatIf: touches no blob and no row' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Remove-ImperionStorageBlob { $true }
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'count\(\*\) AS n') { return @([pscustomobject]@{ n = 0 }) }
                if ($Sql -match 'verified_in_autotask, blob_deleted_at') { return @([pscustomobject]@{ verified_in_autotask = $true; blob_deleted_at = $null }) }
                return @([pscustomobject]@{ id = 'r1'; blob_path = 'receipts/x.pdf' })
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            Invoke-ImperionReceiptLifecycle -Connection (& $makeConnection) -WhatIf | Out-Null

            Should -Invoke Remove-ImperionStorageBlob -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'passes the configured RetentionDays into the cutoff and flagged queries' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Remove-ImperionStorageBlob { $true }
            $script:seenDays = [System.Collections.Generic.List[int]]::new()
            Mock Invoke-ImperionDbQuery {
                if ($Parameters.ContainsKey('days')) { $script:seenDays.Add([int]$Parameters['days']) }
                if ($Sql -match 'count\(\*\) AS n') { return @([pscustomobject]@{ n = 0 }) }
                return @()
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            Invoke-ImperionReceiptLifecycle -Connection (& $makeConnection) -RetentionDays 30 | Out-Null

            $script:seenDays | Should -Contain 30
            $script:seenDays | Should -Not -Contain 90
        }
    }

    It 'isolates a failing receipt: counts it failed and continues the batch' {
        InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
            param($makeConnection)
            Mock Write-ImperionLog { }
            Mock Remove-ImperionStorageBlob { throw 'storage 503' }
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'count\(\*\) AS n') { return @([pscustomobject]@{ n = 0 }) }
                if ($Sql -match 'verified_in_autotask, blob_deleted_at') { return @([pscustomobject]@{ verified_in_autotask = $true; blob_deleted_at = $null }) }
                return @([pscustomobject]@{ id = 'r1'; blob_path = 'receipts/x.pdf' })
            }
            Mock Invoke-ImperionDbNonQuery { 1 }

            $tally = Invoke-ImperionReceiptLifecycle -Connection (& $makeConnection) -Confirm:$false

            $tally.failed | Should -Be 1
            $tally.deleted | Should -Be 0
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Error' }
        }
    }
}
