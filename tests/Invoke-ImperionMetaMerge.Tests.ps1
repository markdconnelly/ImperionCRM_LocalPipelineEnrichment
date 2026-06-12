#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionMetaMerge: ShouldProcess gating and the
# idempotency contracts pinned in the merge SQL (issue #126 / front-end migration 0075).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionMetaMerge' {
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
            Invoke-ImperionMetaMerge -WhatIf | Out-Null
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

        It 'runs all nine steps and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionMetaMerge -Confirm:$false
                $script:capturedMergeSql.Count | Should -Be 9
                $tally.facebook_posts_to_interaction | Should -Be 1
                $tally.social_metrics_merged | Should -Be 1
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Meta merge complete' }
            }
        }

        It 'every interaction insert is gated by NOT EXISTS on (source, external_ref)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $interactionInserts = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO interaction' })
                $interactionInserts.Count | Should -Be 5
                foreach ($sql in $interactionInserts) {
                    $sql | Should -Match '(?s)NOT EXISTS \(SELECT 1 FROM interaction i\s+WHERE i\.source = '
                    $sql | Should -Match 'i\.external_ref = b\.external_id'
                }
            }
        }

        It 'stamps the locked kinds, sources, and directions per bronze table' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $bySql = @{}
                foreach ($table in 'facebook_posts', 'facebook_comments', 'instagram_media', 'instagram_comments', 'facebook_messages') {
                    $bySql[$table] = @($script:capturedMergeSql | Where-Object { $_ -match "FROM $table b" })[0]
                }
                $bySql['facebook_posts'] | Should -Match "'facebook'::interaction_source, 'social_post'"
                $bySql['facebook_posts'] | Should -Match "'outbound'::interaction_direction"
                $bySql['facebook_comments'] | Should -Match "'social_comment'"
                $bySql['facebook_comments'] | Should -Match "'inbound'::interaction_direction"
                $bySql['instagram_media'] | Should -Match "'instagram'::interaction_source, 'social_post'"
                $bySql['instagram_comments'] | Should -Match "'instagram'::interaction_source, 'social_comment'"
                $bySql['facebook_messages'] | Should -Match "'dm'"
            }
        }

        It 'DM direction flips on from_id = page_id (page outbound, sender inbound)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $dmSql = @($script:capturedMergeSql | Where-Object { $_ -match 'FROM facebook_messages b' })[0]
                $dmSql | Should -Match "(?s)CASE WHEN b\.from_id = b\.page_id THEN 'outbound'::interaction_direction\s+ELSE 'inbound'::interaction_direction END"
            }
        }

        It 'ensures ONE facebook_dm hook and ONE lead per DM sender (not per message)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $hookSql = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO lead_hook' })[0]
                $hookSql | Should -Match "(?s)NOT EXISTS \(SELECT 1 FROM lead_hook\s+WHERE kind = 'facebook_dm' AND name = 'Facebook page inbox'\)"

                $captureSql = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO lead_capture_event' })[0]
                # one row per sender: DISTINCT ON (from_id), keyed on hook + payload from_id
                $captureSql | Should -Match 'DISTINCT ON \(from_id\)'
                $captureSql | Should -Match "e\.payload_bronze->>'from_id' = s\.from_id"
                # inbound senders only - the page's own messages never become leads
                $captureSql | Should -Match 'from_id <> page_id'
            }
        }

        It 'contact creation skips senders already known via contact_social_identity' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $contactSql = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO contact ' })[0]
                $contactSql | Should -Match "(?s)NOT EXISTS \(SELECT 1 FROM contact_social_identity csi\s+WHERE csi\.platform = 'facebook' AND csi\.external_id = s\.from_id\)"
                $contactSql | Should -Match 'INSERT INTO contact_social_identity'
            }
        }

        It 'social_metric upsert maps entity_kind to platform and is ON CONFLICT DO NOTHING' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $metricSql = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO social_metric' })[0]
                $metricSql | Should -Match "CASE WHEN b\.entity_kind = 'page' THEN 'facebook' ELSE 'instagram' END"
                $metricSql | Should -Match 'ON CONFLICT \(platform, entity_kind, entity_external_id, metric, period, captured_at\) DO NOTHING'
                # guarded numeric cast - junk text lands NULL, never throws
                $metricSql | Should -Match ([regex]::Escape("CASE WHEN b.value ~ '^-?\d+(\.\d+)?`$' THEN b.value::numeric END"))
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionMetaMerge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}
