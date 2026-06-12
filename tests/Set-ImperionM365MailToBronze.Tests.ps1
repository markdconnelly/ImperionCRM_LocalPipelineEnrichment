#Requires -Modules Pester
# Hermetic test for Set-ImperionM365MailToBronze: standard envelope projected to the exact
# m365_mail_messages column set (front-end migration 0065). Mocked DB seams.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionM365MailToBronze' {
    It 'projects rows to the migration-0065 column set and change-detect upserts m365_mail_messages' {
        InModuleScope ImperionPipeline {
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
                    mailbox = 'ada@imperionllc.com'; subject = 'Quote'; from_address = 'jane@acme.com'
                    from_name = 'Jane'; to_addresses = 'ada@imperionllc.com'; cc_addresses = $null
                    received_date_time = '2026-06-10T10:00:00Z'; sent_date_time = '2026-06-10T09:59:00Z'
                    conversation_id = 'c1'; has_attachments = 'False'; importance = 'normal'
                    is_read = 'True'; web_link = 'https://outlook'; future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365_email'; external_id = 'msg-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionM365MailToBronze

            $script:captured.Table    | Should -Be 'm365_mail_messages'
            $script:captured.NoChange | Should -BeFalse
            ($script:captured.Rows[0].PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'mailbox', 'subject', 'from_address', 'from_name', 'to_addresses', 'cc_addresses',
                    'received_date_time', 'sent_date_time', 'conversation_id', 'has_attachments',
                    'importance', 'is_read', 'web_link',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionM365MailToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ subject = 's'; external_id = 'm'; content_hash = 'h' }
            { $row | Set-ImperionM365MailToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
