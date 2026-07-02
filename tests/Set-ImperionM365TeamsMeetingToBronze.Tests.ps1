#Requires -Modules Pester
# Hermetic test for Set-ImperionM365TeamsMeetingToBronze: user -> user_upn rename + the exact
# m365_teams_meetings column set (front-end migration 0065). Mocked DB seams.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionM365TeamsMeetingToBronze' {
    It 'renames user -> user_upn and projects to the migration-0065 column set' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{
                    user = 'ada@imperionllc.com'; subject = 'QBR'; organizer_address = 'ada@imperionllc.com'
                    attendee_addresses = 'jane@acme.com'; start_date_time = '2026-06-12T15:00:00'
                    end_date_time = '2026-06-12T16:00:00'; is_online_meeting = 'True'
                    online_meeting_provider = 'teamsForBusiness'; join_url = 'https://teams/join'
                    is_cancelled = 'False'; web_link = 'https://outlook'
                    tenant_id = 't1'; source = 'm365_teams'; external_id = 'evt-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            ($rows | Set-ImperionM365TeamsMeetingToBronze).scanned | Should -Be 1

            $script:captured.Table | Should -Be 'm365_teams_meetings'
            $projected = $script:captured.Rows[0]
            $projected.user_upn | Should -Be 'ada@imperionllc.com'
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'user_upn', 'subject', 'organizer_address', 'attendee_addresses',
                    'start_date_time', 'end_date_time', 'is_online_meeting',
                    'online_meeting_provider', 'join_url', 'is_cancelled', 'web_link',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionM365TeamsMeetingToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ user = 'u'; external_id = 'e'; content_hash = 'h' }
            { $row | Set-ImperionM365TeamsMeetingToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
