#Requires -Modules Pester
# Hermetic test for Set-ImperionAzureResourceToBronze: standard envelope, projected to the
# exact azure_resources column set (migration 0038). DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionAzureResourceToBronze' {
    It 'projects rows to the migration-0038 column set and change-detect upserts azure_resources' {
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

            # A future_extra column must be dropped; a missing optional column (kind) lands NULL.
            $rows = @(
                [pscustomobject]@{
                    name = 'vm-01'; type = 'Microsoft.Compute/virtualMachines'; location = 'centralus'
                    resource_group = 'rg-prod'; subscription_id = 'sub-1'; sku = 'Standard_B2s'; tags = 'env=prd'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'azure'; external_id = '/subscriptions/sub-1/.../vm-01'
                    collected_at = '2026-06-09T00:00:00Z'; raw_payload = '{"a":1}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionAzureResourceToBronze

            $script:captured.Table    | Should -Be 'azure_resources'
            $script:captured.Keys     | Should -BeNullOrEmpty   # no override -> upsert's standard-envelope default key
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'name', 'type', 'location', 'resource_group', 'subscription_id', 'sku', 'kind', 'tags',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.name | Should -Be 'vm-01'
            $projected.kind | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $tally.scanned  | Should -Be 1
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
            $row = [pscustomobject]@{ name = 'vm'; external_id = 'res-id'; content_hash = 'h' }

            { $row | Set-ImperionAzureResourceToBronze -Connection $conn } | Should -Not -Throw
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

            $tally = @() | Set-ImperionAzureResourceToBronze
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

            $row = [pscustomobject]@{ name = 'vm'; external_id = 'res-id'; content_hash = 'h' }
            { $row | Set-ImperionAzureResourceToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
