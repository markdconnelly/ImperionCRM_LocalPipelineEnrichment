#Requires -Modules Pester
# Hermetic test for Set-ImperionPlaudRecordingToBronze: standard envelope, projected to the
# PROPOSED plaud_recordings column set (front-end migration pending, issue #72). Mocked seams.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionPlaudRecordingToBronze' {
    It 'projects rows to the proposed plaud_recordings column set and change-detect upserts' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{
                    title = 'Acme kickoff'; started_at = '2026-06-10T15:00:00Z'; duration_seconds = '1800'
                    summary = 'Agreed rollout plan.'; action_items = 'Send SOW'; transcript = 'Mark: hello.'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'plaud'; external_id = 'f1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionPlaudRecordingToBronze

            $script:captured.Table    | Should -Be 'plaud_recordings'
            $script:captured.NoChange | Should -BeFalse
            ($script:captured.Rows[0].PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'title', 'started_at', 'duration_seconds', 'summary', 'action_items', 'transcript',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionPlaudRecordingToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ title = 't'; external_id = 'f'; content_hash = 'h' }
            { $row | Set-ImperionPlaudRecordingToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
