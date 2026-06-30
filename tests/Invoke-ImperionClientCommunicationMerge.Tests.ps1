#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionClientCommunicationMerge: ShouldProcess gating and the
# filter / idempotency / column contracts pinned in the merge SQL (LP #395 / front-end migration
# 0211 / ADR-0126). No live DB — Invoke-ImperionDbNonQuery is mocked and its SQL captured.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionClientCommunicationMerge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
        }
    }

    It 'honors -WhatIf: no connection, no SQL' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbNonQuery { 0 }
            Invoke-ImperionClientCommunicationMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    Context 'merge SQL contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                $script:capturedSql = [System.Collections.Generic.List[string]]::new()
                $script:capturedParams = [System.Collections.Generic.List[hashtable]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:capturedSql.Add($Sql); $script:capturedParams.Add($Parameters); 1 }
            }
        }

        It 'runs the three M365 channel steps and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionClientCommunicationMerge -Confirm:$false
                $script:capturedSql.Count | Should -Be 3
                $tally.mail_to_client_communication          | Should -Be 1
                $tally.teams_chat_to_client_communication     | Should -Be 1
                $tally.teams_meeting_to_client_communication  | Should -Be 1
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Merge plan complete' }
            }
        }

        It 'every insert targets client_communication and upserts on the 0211 idempotency key with content_hash change detection' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionClientCommunicationMerge -Confirm:$false | Out-Null
                foreach ($sql in $script:capturedSql) {
                    $sql | Should -Match 'INSERT INTO client_communication'
                    $sql | Should -Match 'ON CONFLICT \(channel, source_system, external_id\) DO UPDATE'
                    $sql | Should -Match 'content_hash IS DISTINCT FROM EXCLUDED\.content_hash'
                }
            }
        }

        It 'applies the filter gate: drops rows that resolve to no single account' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionClientCommunicationMerge -Confirm:$false | Out-Null
                foreach ($sql in $script:capturedSql) {
                    # the account/contact resolver + the WHERE that drops unattributable rows
                    $sql | Should -Match 'FROM contact c'
                    $sql | Should -Match 'FROM account_domain ad'
                    $sql | Should -Match 'WHERE acc\.account_id IS NOT NULL'
                }
            }
        }

        It 'lands the right channel + source_system per step and stays PII-minimal (no body, client_pii)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionClientCommunicationMerge -Confirm:$false | Out-Null
                $mail    = $script:capturedSql[0]
                $chat    = $script:capturedSql[1]
                $meeting = $script:capturedSql[2]
                $mail    | Should -Match "'email'::client_communication_channel"
                $mail    | Should -Match "FROM m365_mail_messages"
                $mail    | Should -Match "'m365_email', res\.external_id"
                $chat    | Should -Match "'teams_chat'::client_communication_channel"
                $chat    | Should -Match "FROM m365_teams_chats"
                $meeting | Should -Match "'teams_meeting'::client_communication_channel"
                $meeting | Should -Match "FROM m365_teams_meetings"
                foreach ($sql in $script:capturedSql) {
                    $sql | Should -Match "'client_pii'"
                }
            }
        }

        It 'derives direction from sender (mail) / organizer (meeting); chat is inbound by convention' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionClientCommunicationMerge -Confirm:$false | Out-Null
                $script:capturedSql[0] | Should -Match "split_part\(res\.from_addr,'@',2\) = ANY \(@imperionDomains\)"
                $script:capturedSql[2] | Should -Match "split_part\(res\.organizer_addr,'@',2\) = ANY \(@imperionDomains\)"
                $script:capturedSql[1] | Should -Match "'inbound'::client_communication_direction"
            }
        }

        It 'passes the lower-cased Imperion domain set as the imperionDomains parameter' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionClientCommunicationMerge -Confirm:$false -ImperionDomain 'ImperionLLC.com','Foo.COM' | Out-Null
                foreach ($p in $script:capturedParams) {
                    $p.imperionDomains | Should -Be @('imperionllc.com', 'foo.com')
                }
            }
        }
    }
}
