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

        It 'runs all fifteen steps and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionMetaMerge -Confirm:$false
                # 6 interaction inserts + FB lead(hook/contacts/captures) + IG lead(hook/contacts/captures)
                # + social_metric + 2 social_dm → client_communication (#383)
                $script:capturedMergeSql.Count | Should -Be 15
                $tally.facebook_posts_to_interaction | Should -Be 1
                $tally.instagram_messages_to_interaction | Should -Be 1
                $tally.ig_lead_captures_created | Should -Be 1
                $tally.social_metrics_merged | Should -Be 1
                $tally.fb_dm_to_client_communication | Should -Be 1
                $tally.ig_dm_to_client_communication | Should -Be 1
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Meta merge complete' }
            }
        }

        It 'folds DMs into client_communication (social_dm) only when a linked client contact resolves' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $dmInserts = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO client_communication' })
                $dmInserts.Count | Should -Be 2
                foreach ($sql in $dmInserts) {
                    # the filter gate: an INNER JOIN LATERAL to contact_social_identity → contact (account-linked)
                    $sql | Should -Match "(?s)JOIN LATERAL \(\s*SELECT c\.account_id, c\.id AS contact_id\s+FROM contact_social_identity csi\s+JOIN contact c ON c\.id = csi\.contact_id"
                    $sql | Should -Match "c\.account_id IS NOT NULL"
                    $sql | Should -Match "'social_dm'::client_communication_channel"
                    # PII-minimal: subject NULL, snippet truncated preview (never the full body)
                    $sql | Should -Match 'left\(b\.message, 280\)'
                    $sql | Should -Match "'client_pii'"
                    # idempotent on the 0211 key with content_hash change detection
                    $sql | Should -Match 'ON CONFLICT \(channel, source_system, external_id\) DO UPDATE'
                    $sql | Should -Match 'content_hash IS DISTINCT FROM EXCLUDED\.content_hash'
                }
                # provenance labels + the platform-specific identity match
                @($dmInserts | Where-Object { $_ -match "'meta_messenger'" }).Count | Should -Be 1
                @($dmInserts | Where-Object { $_ -match "'instagram_dm'"   }).Count | Should -Be 1
                @($dmInserts | Where-Object { $_ -match "csi\.platform = 'facebook'"  }).Count | Should -Be 1
                @($dmInserts | Where-Object { $_ -match "csi\.platform = 'instagram'" }).Count | Should -Be 1
            }
        }

        It 'every interaction insert is gated by NOT EXISTS on (source, external_ref)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $interactionInserts = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO interaction' })
                $interactionInserts.Count | Should -Be 6
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

                $igDm = @($script:capturedMergeSql | Where-Object { $_ -match 'FROM instagram_messages b' })[0]
                $igDm | Should -Match "'instagram'::interaction_source, 'dm'"
            }
        }

        It 'IG DM direction flips on from_id = ig_user_id (account outbound, sender inbound)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $igDm = @($script:capturedMergeSql | Where-Object { $_ -match 'FROM instagram_messages b' })[0]
                $igDm | Should -Match "(?s)CASE WHEN b\.from_id = b\.ig_user_id THEN 'outbound'::interaction_direction\s+ELSE 'inbound'::interaction_direction END"
            }
        }

        It 'ensures ONE instagram_dm hook + IG identity on platform instagram, one lead per sender' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaMerge -Confirm:$false | Out-Null
                $igHook = @($script:capturedMergeSql | Where-Object { $_ -match "kind = 'instagram_dm'" -and $_ -match 'INSERT INTO lead_hook' })[0]
                $igHook | Should -Match "(?s)NOT EXISTS \(SELECT 1 FROM lead_hook\s+WHERE kind = 'instagram_dm' AND name = 'Instagram direct messages'\)"

                $igContact = @($script:capturedMergeSql | Where-Object { $_ -match "csi\.platform = 'instagram'" -and $_ -match 'INSERT INTO contact ' })[0]
                $igContact | Should -Match "INSERT INTO contact_social_identity"
                $igContact | Should -Match "'instagram', nc\.from_id"

                $igCapture = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO lead_capture_event' -and $_ -match 'ig_user_id' })[0]
                $igCapture | Should -Match 'DISTINCT ON \(from_id\)'
                $igCapture | Should -Match 'from_id <> ig_user_id'
                $igCapture | Should -Match "e\.payload_bronze->>'from_id' = s\.from_id"
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
