#Requires -Modules Pester
# Hermetic test for Set-ImperionAutotaskTicketToBronze: DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionAutotaskTicketToBronze' {
    It 'upserts piped rows into autotask_tickets and disposes its own connection' {
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
                [pscustomobject]@{ external_id = '10'; source = 'autotask'; tenant_id = 't1'; content_hash = 'a' }
                [pscustomobject]@{ external_id = '11'; source = 'autotask'; tenant_id = 't1'; content_hash = 'b' }
            )
            $tally = $rows | Set-ImperionAutotaskTicketToBronze

            $script:captured.Table | Should -Be 'autotask_tickets'
            $tally.scanned | Should -Be 2
            $script:opened | Should -Be 1
            $script:disposed | Should -Be 1
        }
    }

    It 'writes nothing and opens no connection for empty input' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection for 0 rows' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert 0 rows' }

            (@() | Set-ImperionAutotaskTicketToBronze).scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
