#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionSocialEngagementMerge: ShouldProcess gating and the
# idempotency / column contracts pinned in the merge SQL (slice H #357 / front-end migration 0210).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionSocialEngagementMerge' {
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
            Invoke-ImperionSocialEngagementMerge -WhatIf | Out-Null
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

        It 'runs both comment steps and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionSocialEngagementMerge -Confirm:$false
                $script:capturedMergeSql.Count | Should -Be 2
                $tally.facebook_comments_to_engagement | Should -Be 1
                $tally.instagram_comments_to_engagement | Should -Be 1
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Social engagement merge complete' }
            }
        }

        It 'every insert targets social_engagement, kind comment, and is ON CONFLICT (channel, external_id) DO NOTHING' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSocialEngagementMerge -Confirm:$false | Out-Null
                foreach ($sql in $script:capturedMergeSql) {
                    $sql | Should -Match 'INSERT INTO social_engagement'
                    $sql | Should -Match "'comment'::social_engagement_kind"
                    $sql | Should -Match 'ON CONFLICT \(channel, external_id\) DO NOTHING'
                }
            }
        }

        It 'stamps the channel per bronze table' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSocialEngagementMerge -Confirm:$false | Out-Null
                $fb = @($script:capturedMergeSql | Where-Object { $_ -match 'FROM facebook_comments b' })[0]
                $ig = @($script:capturedMergeSql | Where-Object { $_ -match 'FROM instagram_comments b' })[0]
                $fb | Should -Match "'facebook'::social_channel"
                $ig | Should -Match "'instagram'::social_channel"
            }
        }

        It 'lands ONLY ingestion-owned columns — never contact_id / intent / assigned_agent_key / status (slice G + triage own those)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSocialEngagementMerge -Confirm:$false | Out-Null
                foreach ($sql in $script:capturedMergeSql) {
                    # the INSERT column list must not name the deferred columns
                    $insertList = ($sql -split 'SELECT')[0]
                    $insertList | Should -Not -Match 'contact_id'
                    $insertList | Should -Not -Match 'intent'
                    $insertList | Should -Not -Match 'assigned_agent_key'
                    $insertList | Should -Not -Match '\bstatus\b'
                    # but it must carry the author fields + body + posted_at
                    $insertList | Should -Match 'author_external_id'
                    $insertList | Should -Match 'author_handle'
                    $insertList | Should -Match 'body'
                    $insertList | Should -Match 'posted_at'
                }
            }
        }

        It 'casts the bronze created_time with a regex guard (collected_at fallback)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSocialEngagementMerge -Confirm:$false | Out-Null
                foreach ($sql in $script:capturedMergeSql) {
                    $sql | Should -Match ([regex]::Escape("CASE WHEN b.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN b.created_time::timestamptz"))
                    $sql | Should -Match 'ELSE b\.collected_at::timestamptz END'
                }
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionSocialEngagementMerge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}
