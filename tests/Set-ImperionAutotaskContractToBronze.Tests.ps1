#Requires -Modules Pester
# Hermetic test for Set-ImperionAutotaskContractToBronze: DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionAutotaskContractToBronze' {
    It 'pipes flattened rows into a change-detected upsert on autotask_contracts' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            $script:opened = 0; $script:disposed = 0
            Mock New-ImperionDbConnection {
                $script:opened++
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{ external_id = '1'; source = 'autotask'; tenant_id = 't1'; content_hash = 'a' }
                [pscustomobject]@{ external_id = '2'; source = 'autotask'; tenant_id = 't1'; content_hash = 'b' }
            )
            $tally = $rows | Set-ImperionAutotaskContractToBronze

            $script:captured.Table | Should -Be 'autotask_contracts'
            @($script:captured.Rows).Count | Should -Be 2
            $tally.scanned | Should -Be 2
            $script:opened | Should -Be 1      # opened its own connection...
            $script:disposed | Should -Be 1    # ...and disposed it
        }
    }

    It 'reuses a supplied connection and does not open or dispose one' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open its own connection' }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            $script:externalDisposed = 0
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:externalDisposed++ }
            $row = [pscustomobject]@{ external_id = '1'; content_hash = 'a' }

            { $row | Set-ImperionAutotaskContractToBronze -Connection $conn } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 1
            $script:externalDisposed | Should -Be 0   # caller owns the connection
        }
    }

    It 'writes nothing and opens no connection for empty input' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }

            $tally = @() | Set-ImperionAutotaskContractToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honours -WhatIf: no upsert, no connection' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection under -WhatIf' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert under -WhatIf' }

            $row = [pscustomobject]@{ external_id = '1'; content_hash = 'a' }
            { $row | Set-ImperionAutotaskContractToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
