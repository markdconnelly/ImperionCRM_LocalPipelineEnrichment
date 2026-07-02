#Requires -Modules Pester
# Hermetic test for Invoke-ImperionBronzePost, the shared post-writer scaffold behind every
# Set-Imperion*ToBronze adapter (issue #105): envelope shaping, ShouldProcess delegation,
# own-vs-reuse connection lifecycle, upsert forwarding, metric log, tally passthrough.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionBronzePost' {
    It 'returns a zero tally, logs, and opens no connection for empty input' {
        InModuleScope ImperionPipeline {
            $script:logged = $null
            Mock Write-ImperionLog { $script:logged = @{ Source = $Source; Message = $Message } }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }

            $tally = Invoke-ImperionBronzePost -Rows @() -Table 'some_table' -LogSource 'autotask'

            $tally.scanned | Should -Be 0
            $tally.inserted | Should -Be 0
            $script:logged.Source | Should -Be 'autotask'
            $script:logged.Message | Should -Be 'some_table: 0 rows to write.'
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'standard envelope: passes rows through untouched with no key/json/change overrides' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            $script:opened = 0; $script:disposed = 0
            Mock New-ImperionDbConnection {
                $script:opened++
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; Keys = $KeyColumns; Json = $JsonColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = 1; updated = 1; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{ external_id = '1'; source = 's'; tenant_id = 't'; raw_payload = '{}'; content_hash = 'a' }
                [pscustomobject]@{ external_id = '2'; source = 's'; tenant_id = 't'; raw_payload = '{}'; content_hash = 'b' }
            )
            $tally = Invoke-ImperionBronzePost -Rows $rows -Table 'autotask_contracts' -LogSource 'autotask'

            $script:captured.Table | Should -Be 'autotask_contracts'
            @($script:captured.Rows).Count | Should -Be 2
            $script:captured.Rows[0].external_id | Should -Be '1'   # untouched passthrough
            $script:captured.Keys | Should -BeNullOrEmpty           # upsert's standard default key
            $script:captured.Json | Should -BeNullOrEmpty           # upsert's default raw_payload
            $script:captured.NoChange | Should -BeFalse             # change detection stays on
            $tally.inserted | Should -Be 1                          # tally passthrough
            $tally.updated | Should -Be 1
            $script:opened | Should -Be 1      # opened its own connection...
            $script:disposed | Should -Be 1    # ...and disposed it
        }
    }

    It '-PerSourceShape: projects to external_ref/payload_bronze and upserts with -NoChangeDetect' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Rows = $Rows; Keys = $KeyColumns; Json = $JsonColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @([pscustomobject]@{ external_id = 'x1'; raw_payload = '{"a":1}'; source = 's'; tenant_id = 't'; name = 'N' })
            Invoke-ImperionBronzePost -Rows $rows -Table 'televy_reports' -LogSource 'televy' -PerSourceShape | Out-Null

            $script:captured.Keys | Should -Be 'external_ref'
            $script:captured.Json | Should -Be 'payload_bronze'
            $script:captured.NoChange | Should -BeTrue
            $projected = $script:captured.Rows[0]
            $projected.external_ref | Should -Be 'x1'
            $projected.payload_bronze | Should -Be '{"a":1}'
            # standard-envelope business columns are dropped — the table doesn't have them.
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be @('external_ref', 'payload_bronze' | Sort-Object)
        }
    }

    It '-ColumnSet: projects to exactly the named columns; missing land NULL, extras drop' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Assert-ImperionColumnSet { }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Rows = $Rows; Keys = $KeyColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @([pscustomobject]@{ name = 'vm-01'; future_extra = 'dropme'; external_id = 'e1'; content_hash = 'h' })
            Invoke-ImperionBronzePost -Rows $rows -Table 'azure_resources' -LogSource 'azure' `
                -ColumnSet @('name', 'kind', 'external_id', 'content_hash') | Out-Null

            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@('name', 'kind', 'external_id', 'content_hash') | Sort-Object)
            $projected.name | Should -Be 'vm-01'
            $projected.kind | Should -BeNullOrEmpty                 # missing on input -> projected as NULL
            $script:captured.Keys | Should -BeNullOrEmpty           # change detection + standard key stay on
            $script:captured.NoChange | Should -BeFalse
        }
    }

    It '-ColumnSet: runs the drift guard against the live table before the upsert (#427)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            $script:callOrder = [System.Collections.Generic.List[string]]::new()
            $guardCall = $null
            Mock Assert-ImperionColumnSet {
                $script:callOrder.Add('guard')
                $script:guardCall = @{ Table = $Table; ColumnSet = $ColumnSet }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:callOrder.Add('upsert')
                [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 }
            }

            $rows = @([pscustomobject]@{ name = 'vm-01'; external_id = 'e1'; content_hash = 'h' })
            Invoke-ImperionBronzePost -Rows $rows -Table 'azure_resources' -LogSource 'azure' `
                -ColumnSet @('name', 'external_id', 'content_hash') | Out-Null

            $script:callOrder | Should -Be @('guard', 'upsert')       # fail-fast layer: guard BEFORE write
            $script:guardCall.Table | Should -Be 'azure_resources'
            $script:guardCall.ColumnSet | Should -Be @('name', 'external_id', 'content_hash')
        }
    }

    It '-ColumnSet: drift throws before any upsert and still disposes the owned connection (#427)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            $script:disposed = 0
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            Mock Assert-ImperionColumnSet { throw "ColumnSet drift guard: table 'azure_resources' is missing declared column(s): kind." }
            Mock Invoke-ImperionBronzeUpsert { throw 'must never be reached on drift' }

            $rows = @([pscustomobject]@{ name = 'vm-01'; external_id = 'e1'; content_hash = 'h' })
            { Invoke-ImperionBronzePost -Rows $rows -Table 'azure_resources' -LogSource 'azure' `
                    -ColumnSet @('name', 'kind', 'external_id', 'content_hash') } |
                Should -Throw '*missing declared column(s): kind*'

            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
            $script:disposed | Should -Be 1
        }
    }

    It 'skips the drift guard for standard-envelope and -PerSourceShape writes' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Assert-ImperionColumnSet { throw 'guard must not run without -ColumnSet' }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            $rows = @([pscustomobject]@{ external_id = '1'; raw_payload = '{}'; content_hash = 'a' })
            { Invoke-ImperionBronzePost -Rows $rows -Table 't' -LogSource 's' } | Should -Not -Throw
            { Invoke-ImperionBronzePost -Rows $rows -Table 'televy_reports' -LogSource 'televy' -PerSourceShape } | Should -Not -Throw
            Should -Invoke Assert-ImperionColumnSet -Times 0
        }
    }

    It 'reuses a supplied connection and does not open or dispose one' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open its own connection' }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            $script:externalDisposed = 0
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:externalDisposed++ }
            $rows = @([pscustomobject]@{ external_id = '1'; content_hash = 'a' })

            { Invoke-ImperionBronzePost -Rows $rows -Table 't' -LogSource 's' -Connection $conn } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 1
            $script:externalDisposed | Should -Be 0   # caller owns the connection
        }
    }

    It 'disposes its own connection even when the upsert throws' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            $script:disposed = 0
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            Mock Invoke-ImperionBronzeUpsert { throw 'db down' }

            $rows = @([pscustomobject]@{ external_id = '1' })
            { Invoke-ImperionBronzePost -Rows $rows -Table 't' -LogSource 's' } | Should -Throw 'db down'
            $script:disposed | Should -Be 1
        }
    }

    It 'honours the delegated ShouldProcess gate: -WhatIf on the caller means no upsert, no connection, a scanned-only tally' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection under -WhatIf' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert under -WhatIf' }

            # A minimal public-writer stand-in: SupportsShouldProcess + delegate via -CallerCmdlet.
            function Test-ImperionBronzePostCaller {
                [CmdletBinding(SupportsShouldProcess)]
                param([object[]] $Rows)
                Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Rows $Rows -Table 'gate_table' -LogSource 's'
            }

            $rows = @([pscustomobject]@{ external_id = '1' }, [pscustomobject]@{ external_id = '2' })
            $tally = Test-ImperionBronzePostCaller -Rows $rows -WhatIf

            $tally.scanned | Should -Be 2
            $tally.inserted | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'proceeds without a gate when -CallerCmdlet is omitted (router mode: caller already gated)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            $rows = @([pscustomobject]@{ external_id = '1' })
            $tally = Invoke-ImperionBronzePost -Rows $rows -Table 't' -LogSource 's'
            $tally.inserted | Should -Be 1
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 1
        }
    }

    It 'dedupes intra-batch duplicate conflict keys, last occurrence wins (#133)' {
        InModuleScope ImperionPipeline {
            $script:dedupeLog = $null
            Mock Write-ImperionLog { if ($Message -like '*deduped*') { $script:dedupeLog = $Message } }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @($Rows)
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            # The same comment id surfacing under two posts: identical (tenant, source,
            # external_id), different payloads. The LAST row must win.
            $rows = @(
                [pscustomobject]@{ tenant_id = 't'; source = 'facebook'; external_id = 'c1'; post_external_id = 'p1'; content_hash = 'a' }
                [pscustomobject]@{ tenant_id = 't'; source = 'facebook'; external_id = 'c2'; post_external_id = 'p1'; content_hash = 'b' }
                [pscustomobject]@{ tenant_id = 't'; source = 'facebook'; external_id = 'c1'; post_external_id = 'p2'; content_hash = 'c' }
            )
            Invoke-ImperionBronzePost -Rows $rows -Table 'facebook_comments' -LogSource 'meta' | Out-Null

            $script:captured.Count | Should -Be 2
            ($script:captured | Where-Object external_id -eq 'c1').post_external_id | Should -Be 'p2'
            $script:dedupeLog | Should -Be 'facebook_comments: deduped 1 intra-batch duplicate key(s).'
        }
    }

    It 'dedupes on the projected external_ref key under -PerSourceShape' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @($Rows)
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{ external_id = 'x1'; raw_payload = '{"v":1}' }
                [pscustomobject]@{ external_id = 'x1'; raw_payload = '{"v":2}' }
            )
            Invoke-ImperionBronzePost -Rows $rows -Table 'televy_reports' -LogSource 'televy' -PerSourceShape | Out-Null

            $script:captured.Count | Should -Be 1
            $script:captured[0].payload_bronze | Should -Be '{"v":2}'
        }
    }

    It 'emits the metric log line with the table and full tally' {
        InModuleScope ImperionPipeline {
            $script:metricLog = $null
            Mock Write-ImperionLog { if ($Level -eq 'Metric') { $script:metricLog = @{ Source = $Source; Message = $Message; Data = $Data } } }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 3; inserted = 1; updated = 1; unchanged = 1 } }

            $rows = @(1..3 | ForEach-Object { [pscustomobject]@{ external_id = "$_" } })
            Invoke-ImperionBronzePost -Rows $rows -Table 'metric_table' -LogSource 'itglue' | Out-Null

            $script:metricLog.Source | Should -Be 'itglue'
            $script:metricLog.Message | Should -Be 'metric_table written.'
            $script:metricLog.Data.table | Should -Be 'metric_table'
            $script:metricLog.Data.scanned | Should -Be 3
            $script:metricLog.Data.inserted | Should -Be 1
            $script:metricLog.Data.updated | Should -Be 1
            $script:metricLog.Data.unchanged | Should -Be 1
        }
    }
}
