#Requires -Modules Pester
# Hermetic test for Set-ImperionM365TeamsChatToBronze: user -> user_upn rename + the exact
# m365_teams_chats column set (front-end migration 0065). Mocked DB seams.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionM365TeamsChatToBronze' {
    It 'renames user -> user_upn and projects to the migration-0065 column set' {
        InModuleScope ImperionPipeline {
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
                    user = 'ada@imperionllc.com'; topic = 'Acme rollout'; chat_type = 'group'
                    member_emails = 'jane@acme.com; ada@imperionllc.com'; member_names = 'Jane; Ada'
                    created_date_time = '2026-06-01'; last_updated_date_time = '2026-06-10'
                    web_url = 'https://teams'
                    tenant_id = 't1'; source = 'm365_teams'; external_id = 'chat-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            ($rows | Set-ImperionM365TeamsChatToBronze).scanned | Should -Be 1

            $script:captured.Table | Should -Be 'm365_teams_chats'
            $projected = $script:captured.Rows[0]
            $projected.user_upn | Should -Be 'ada@imperionllc.com'
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'user_upn', 'topic', 'chat_type', 'member_emails', 'member_names',
                    'created_date_time', 'last_updated_date_time', 'web_url',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionM365TeamsChatToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ user = 'u'; external_id = 'c'; content_hash = 'h' }
            { $row | Set-ImperionM365TeamsChatToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
