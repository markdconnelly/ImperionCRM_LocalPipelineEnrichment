#Requires -Modules Pester
# Hermetic test for Invoke-ImperionITGlueExportToBronze: per-entity routing into the
# itglue_export_* table set. DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionITGlueExportToBronze' {
    It 'routes a mixed batch by per-row entity, strips the discriminator, and sums the tallies' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            $script:opened = 0; $script:disposed = 0
            Mock New-ImperionDbConnection {
                $script:opened++
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            $script:upserts = @()
            Mock Invoke-ImperionBronzeUpsert {
                $script:upserts += @{ Table = $Table; Rows = $Rows; Keys = $KeyColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{ entity = 'organizations'; source = 'itglue'; external_id = 'o1'; name = 'Org'; raw_payload = '{}'; content_hash = 'a' }
                [pscustomobject]@{ entity = 'configurations'; source = 'itglue'; external_id = 'c1'; name = 'Cfg1'; raw_payload = '{}'; content_hash = 'b' }
                [pscustomobject]@{ entity = 'configurations'; source = 'itglue'; external_id = 'c2'; name = 'Cfg2'; raw_payload = '{}'; content_hash = 'c' }
            )
            $tally = $rows | Invoke-ImperionITGlueExportToBronze

            @($script:upserts).Count | Should -Be 2   # one upsert per routed table
            $byTable = @{}; foreach ($u in $script:upserts) { $byTable[$u.Table] = $u }
            @($byTable['itglue_export_organizations'].Rows).Count  | Should -Be 1
            @($byTable['itglue_export_configurations'].Rows).Count | Should -Be 2
            foreach ($u in $script:upserts) {
                $u.Keys | Should -Be @('source', 'external_id')   # the export tables key on (source, external_id)
                $u.NoChange | Should -BeFalse                     # content_hash change detection stays on
                # the routing discriminator never reaches the table — it has no 'entity' column.
                $u.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'entity'
            }
            $tally.scanned  | Should -Be 3
            $tally.inserted | Should -Be 3
            $script:opened | Should -Be 1      # one shared connection for the whole batch...
            $script:disposed | Should -Be 1    # ...disposed at the end
        }
    }

    It 'applies -Entity to rows without a per-row discriminator' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = 0; updated = @($Rows).Count; unchanged = 0 }
            }

            $row = [pscustomobject]@{ source = 'itglue'; external_id = 'd1'; name = 'example.com'; raw_payload = '{}'; content_hash = 'a' }
            $tally = $row | Invoke-ImperionITGlueExportToBronze -Entity domains

            $script:captured.Table | Should -Be 'itglue_export_domains'
            $tally.updated | Should -Be 1
        }
    }

    It 'fails loudly on an unknown entity (never invents a table)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            $row = [pscustomobject]@{ entity = 'passwords'; source = 'itglue'; external_id = 'p1'; raw_payload = '{}' }
            { $row | Invoke-ImperionITGlueExportToBronze } | Should -Throw "*unknown export entity 'passwords'*"
            { @([pscustomobject]@{ source = 'itglue'; external_id = 'x' }) | Invoke-ImperionITGlueExportToBronze -Entity nope } |
                Should -Throw "*unknown export entity 'nope'*"
        }
    }

    It 'throws when a row has no entity and no -Entity was supplied' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            $row = [pscustomobject]@{ source = 'itglue'; external_id = 'x1'; raw_payload = '{}' }
            { $row | Invoke-ImperionITGlueExportToBronze } | Should -Throw "*no 'entity' property and no -Entity*"
        }
    }

    It 'reuses a supplied connection and does not open or dispose one' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open its own connection' }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            $script:externalDisposed = 0
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:externalDisposed++ }
            $row = [pscustomobject]@{ entity = 'contacts'; source = 'itglue'; external_id = 'c1'; raw_payload = '{}'; content_hash = 'a' }

            { $row | Invoke-ImperionITGlueExportToBronze -Connection $conn } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 1
            $script:externalDisposed | Should -Be 0   # caller owns the connection
        }
    }

    It 'writes nothing and opens no connection for empty input' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }

            $tally = @() | Invoke-ImperionITGlueExportToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honours -WhatIf: no upsert, no connection' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection under -WhatIf' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert under -WhatIf' }

            $row = [pscustomobject]@{ entity = 'organizations'; source = 'itglue'; external_id = 'o1'; raw_payload = '{}' }
            { $row | Invoke-ImperionITGlueExportToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
