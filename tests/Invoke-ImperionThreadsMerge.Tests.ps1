#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionThreadsMerge: ShouldProcess gating + the idempotency
# contracts pinned in the merge SQL (LocalPipeline #356 / front-end migration 0208).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionThreadsMerge' {
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
            Invoke-ImperionThreadsMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    Context 'merge SQL contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                $script:capturedMergeSql = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:capturedMergeSql.Add($Sql); 1 }
            }
        }

        It 'runs all four steps and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionThreadsMerge -Confirm:$false
                # 3 interaction inserts + 1 social_metric
                $script:capturedMergeSql.Count | Should -Be 4
                $tally.threads_posts_to_interaction | Should -Be 1
                $tally.threads_replies_to_interaction | Should -Be 1
                $tally.threads_mentions_to_interaction | Should -Be 1
                $tally.social_metrics_merged | Should -Be 1
            }
        }

        It 'gates every interaction insert on NOT EXISTS (source threads, external_ref)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionThreadsMerge -Confirm:$false | Out-Null
                $interactionInserts = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO interaction' })
                $interactionInserts.Count | Should -Be 3
                foreach ($sql in $interactionInserts) {
                    $sql | Should -Match "i.source = 'threads'"
                    $sql | Should -Match 'NOT EXISTS'
                    $sql | Should -Match 'i.external_ref = b.external_id'
                }
            }
        }

        It 'maps posts outbound, mentions inbound, replies by author' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionThreadsMerge -Confirm:$false | Out-Null
                $posts = $script:capturedMergeSql | Where-Object { $_ -match 'FROM threads_posts' }
                $posts | Should -Match "'social_post'"
                $posts | Should -Match "'outbound'::interaction_direction"
                $mentions = $script:capturedMergeSql | Where-Object { $_ -match 'FROM threads_mentions' }
                $mentions | Should -Match "'mention'"
                $mentions | Should -Match "'inbound'::interaction_direction"
                $replies = $script:capturedMergeSql | Where-Object { $_ -match 'FROM threads_replies' }
                $replies | Should -Match "'social_comment'"
                $replies | Should -Match 'b.threads_user_id = p.threads_user_id'
            }
        }

        It 'merges insights to social_metric with platform threads and ON CONFLICT DO NOTHING' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionThreadsMerge -Confirm:$false | Out-Null
                $metric = $script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO social_metric' }
                $metric | Should -Match "'threads'"
                $metric | Should -Match 'FROM threads_insights'
                $metric | Should -Match 'ON CONFLICT'
                $metric | Should -Match 'DO NOTHING'
            }
        }
    }
}
