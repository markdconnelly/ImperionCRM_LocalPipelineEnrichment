#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeConversationSegment: DB layer mocked. Proves the
# per-segment knowledge_object emit (entity_ref = the segment id — the citation-view key),
# the channel/speaker body framing, the conversation_id in metadata, and the empty short-circuit.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeConversationSegment' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{
                        id = 'seg-1'; conversation_id = 'conv-1'; speaker = 'Agent'
                        start_ms = 0; end_ms = 4200; text = 'Thanks for calling Imperion, how can I help?'
                        source = 'acs'; external_ref = 'acs-call-9'; conversation_started_at = '2026-06-14T15:00:00Z'
                        account_name = 'Acme Co'
                    },
                    [pscustomobject]@{
                        id = 'seg-2'; conversation_id = 'conv-1'; speaker = 'Customer'
                        start_ms = 4300; end_ms = 9000; text = 'Our backups failed again last night.'
                        source = 'acs'; external_ref = 'acs-call-9'; conversation_started_at = '2026-06-14T15:00:00Z'
                        account_name = 'Acme Co'
                    },
                    [pscustomobject]@{
                        id = 'seg-3'; conversation_id = 'conv-2'; speaker = $null
                        start_ms = $null; end_ms = $null; text = 'Quick sync on the Teams migration plan.'
                        source = 'teams'; external_ref = 'teams-mtg-3'; conversation_started_at = '2026-06-13T10:00:00Z'
                        account_name = $null
                    }
                )
            }
        }
    }

    It 'composes one knowledge_object per transcript segment, keyed on the segment id' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeConversationSegment -Connection ([pscustomobject]@{}))
            $rows.Count          | Should -Be 3
            $rows[0].entity_type | Should -Be 'conversation_segment'
            ($rows.entity_ref)   | Should -Be @('seg-1', 'seg-2', 'seg-3')
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
        }
    }

    It 'frames the ACS channel, account, speaker and turn text into the body' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeConversationSegment -Connection ([pscustomobject]@{}))
            $seg = $rows | Where-Object entity_ref -eq 'seg-2'
            $seg.source | Should -Be 'acs'
            $seg.title  | Should -Match 'Call \(Acme Co\)'
            $seg.title  | Should -Match 'Customer:'
            $seg.body   | Should -Match 'Account: Acme Co'
            $seg.body   | Should -Match 'Customer: Our backups failed again'
            $seg.body   | Should -Match 'start: 4300ms'
        }
    }

    It 'carries the parent conversation id and account in metadata (the citation path)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeConversationSegment -Connection ([pscustomobject]@{}))
            $meta = ($rows | Where-Object entity_ref -eq 'seg-1').metadata | ConvertFrom-Json
            $meta.conversation_id | Should -Be 'conv-1'
            $meta.source          | Should -Be 'acs'
            $meta.speaker         | Should -Be 'Agent'
            $meta.account         | Should -Be 'Acme Co'
        }
    }

    It 'labels the Teams channel and falls back to a generic speaker when undiarized' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeConversationSegment -Connection ([pscustomobject]@{}))
            $seg = $rows | Where-Object entity_ref -eq 'seg-3'
            $seg.title | Should -Match 'Teams meeting'
            $seg.body  | Should -Match 'Speaker: Quick sync'
        }
    }

    It 'returns nothing (and does not throw) when silver has no transcript segments' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeConversationSegment -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
