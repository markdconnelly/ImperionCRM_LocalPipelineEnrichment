#Requires -Modules Pester
# Hermetic test for Set-ImperionAzureSubscriptionToBronze: standard envelope, projected to the
# exact azure_subscriptions column set (migration 0038). DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionAzureSubscriptionToBronze' {
    It 'projects rows to the migration-0038 column set and change-detect upserts azure_subscriptions' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            $script:opened = 0; $script:disposed = 0
            Mock New-ImperionDbConnection {
                $script:opened++
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; Keys = $KeyColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            # Collector over-collects: authorization_source/quota_id/spending_limit are NOT
            # azure_subscriptions columns and must be dropped from the flat projection.
            $rows = @(
                [pscustomobject]@{
                    display_name = 'Prod'; state = 'Enabled'; sub_tenant_id = 'st1'
                    authorization_source = 'RoleBased'; quota_id = 'PayAsYouGo'; spending_limit = 'Off'
                    tenant_id = 't1'; source = 'azure'; external_id = 'sub-1'
                    collected_at = '2026-06-09T00:00:00Z'; raw_payload = '{"a":1}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionAzureSubscriptionToBronze

            $script:captured.Table    | Should -Be 'azure_subscriptions'
            $script:captured.Keys     | Should -BeNullOrEmpty   # no override -> upsert's standard-envelope default key
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'display_name', 'state', 'sub_tenant_id',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.display_name | Should -Be 'Prod'
            $projected.external_id  | Should -Be 'sub-1'
            $projected.content_hash | Should -Be 'h1'
            $tally.scanned | Should -Be 1
            $script:opened | Should -Be 1      # opened its own connection...
            $script:disposed | Should -Be 1    # ...and disposed it
        }
    }

    It 'reuses a supplied connection and does not open or dispose one' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open its own connection' }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            $script:externalDisposed = 0
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:externalDisposed++ }
            $row = [pscustomobject]@{ display_name = 'P'; external_id = 'sub-1'; content_hash = 'h' }

            { $row | Set-ImperionAzureSubscriptionToBronze -Connection $conn } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 1
            $script:externalDisposed | Should -Be 0   # caller owns the connection
        }
    }

    It 'writes nothing and opens no connection for empty input' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }

            $tally = @() | Set-ImperionAzureSubscriptionToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honours -WhatIf: no upsert, no connection' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection under -WhatIf' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert under -WhatIf' }

            $row = [pscustomobject]@{ display_name = 'P'; external_id = 'sub-1'; content_hash = 'h' }
            { $row | Set-ImperionAzureSubscriptionToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
