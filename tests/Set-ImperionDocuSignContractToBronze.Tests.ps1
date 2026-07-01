#Requires -Modules Pester
# Hermetic test for Set-ImperionDocuSignContractToBronze: standard envelope, projected to the
# exact docusign_contracts column set (migration 0038). DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionDocuSignContractToBronze' {
    It 'projects rows to the migration-0038 column set and change-detect upserts docusign_contracts' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            $script:opened = 0; $script:disposed = 0
            Mock New-ImperionDbConnection {
                $script:opened++
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $script:disposed++ }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; Keys = $KeyColumns; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            # A future_extra column must be dropped; a missing optional column (completed_at) lands NULL.
            $rows = @(
                [pscustomobject]@{
                    subject = 'MSA — Acme Corp'; status = 'sent'; account_ref = 'jane@acme.com'
                    sent_at = '2026-05-01T12:00:00Z'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'docusign'; external_id = 'env-1'
                    collected_at = '2026-06-11T00:00:00Z'; raw_payload = '{"a":1}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionDocuSignContractToBronze

            $script:captured.Table    | Should -Be 'docusign_contracts'
            $script:captured.Keys     | Should -BeNullOrEmpty   # standard-envelope default key
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'subject', 'status', 'account_ref', 'sent_at', 'completed_at',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.subject      | Should -Be 'MSA — Acme Corp'
            $projected.completed_at | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $tally.scanned | Should -Be 1
            $script:opened | Should -Be 1
            $script:disposed | Should -Be 1
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
            $row = [pscustomobject]@{ subject = 'NDA'; external_id = 'env-2'; content_hash = 'h' }

            { $row | Set-ImperionDocuSignContractToBronze -Connection $conn } | Should -Not -Throw
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

            $tally = @() | Set-ImperionDocuSignContractToBronze
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

            $row = [pscustomobject]@{ subject = 'NDA'; external_id = 'env-2'; content_hash = 'h' }
            { $row | Set-ImperionDocuSignContractToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
