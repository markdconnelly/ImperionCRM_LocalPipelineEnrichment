#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeMemory: DB layer mocked. Proves the per-conversation
# gold `memory` knowledge_object emit (entity_ref = conversation_id — the drill-down key,
# ADR-0113), the scope facets in metadata (wing/room/agent_slug — the EXACT keys the backend
# recall path filters on), the assembled transcript body, and the empty short-circuit. The
# mocked query returns rows ALREADY GROUPED (the composer's SQL does the GROUP BY).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeMemory' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{
                        conversation_id = 'conv-1'; turn_count = 2; last_turn_at = '2026-06-20T12:00:00Z'
                        wing = 'company'; room = 'service'; agent_slug = 'felix'; owner_user_id = 'user-9'
                        transcript = "user: backups keep failing for Acme`nassistant: opened a ticket and scheduled a fix"
                    },
                    [pscustomobject]@{
                        conversation_id = 'conv-2'; turn_count = 1; last_turn_at = '2026-06-19T09:30:00Z'
                        wing = $null; room = $null; agent_slug = $null; owner_user_id = 'user-3'
                        transcript = 'note: remember Mark prefers terse summaries'
                    }
                )
            }
        }
    }

    It 'composes one gold memory knowledge_object per conversation, keyed on conversation_id' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeMemory -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 2
            $rows[0].entity_type  | Should -Be 'memory'
            ($rows.entity_ref)    | Should -Be @('conv-1', 'conv-2')
            $rows[0].source       | Should -Be 'memory_drawer'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
        }
    }

    It 'frames the scope facets into the title and assembles the ordered transcript into the body' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeMemory -Connection ([pscustomobject]@{}))
            $thread = $rows | Where-Object entity_ref -eq 'conv-1'
            $thread.title | Should -Match 'wing: company'
            $thread.title | Should -Match 'agent: felix'
            $thread.title | Should -Match '2 turns'
            $thread.body  | Should -Match 'user: backups keep failing'
            $thread.body  | Should -Match 'assistant: opened a ticket'
        }
    }

    It 'carries the recall facet keys (conversation_id, wing, room, agent_slug) in metadata' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeMemory -Connection ([pscustomobject]@{}))
            $meta = ($rows | Where-Object entity_ref -eq 'conv-1').metadata | ConvertFrom-Json
            $meta.conversation_id | Should -Be 'conv-1'
            $meta.wing            | Should -Be 'company'
            $meta.room            | Should -Be 'service'
            $meta.agent_slug      | Should -Be 'felix'
            $meta.turn_count      | Should -Be 2
        }
    }

    It 'falls back to a generic title (no scope bits) and singular turn label when unscoped' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeMemory -Connection ([pscustomobject]@{}))
            $thread = $rows | Where-Object entity_ref -eq 'conv-2'
            $thread.title | Should -Match 'Memory thread \(1 turn\)'
            $thread.body  | Should -Match 'note: remember Mark prefers terse summaries'
        }
    }

    It 'returns nothing (and does not throw) when memory_drawer has no rows' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeMemory -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
