#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionScopedInteractionMailToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionScopedInteractionMailToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the m365_email column set and upserts on external_id (the message id)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                message_id = 'AAMk-1'; conversation_id = 'conv-1'; subject = 'Hi'; preview = 'p'; from_address = 'derek@imperionllc.com'
                to_recipients = 'sam@acme.com'; direction = 'outbound'; sent_at = '2026-06-05T10:00:00Z'; has_attachments = $false; mailbox_owner = 'derek@imperionllc.com'
                tenant_id = 't1'; source = 'm365_email'; external_id = 'AAMk-1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionScopedInteractionMailToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'm365_email'
            $captured.Rows[0].external_id | Should -Be 'AAMk-1'
            $captured.Rows[0].direction | Should -Be 'outbound'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionScopedInteractionMailToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ message_id = 'm'; tenant_id = 't'; source = 'm365_email'; external_id = 'm'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionScopedInteractionMailToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
