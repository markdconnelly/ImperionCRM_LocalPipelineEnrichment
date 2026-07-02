#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeAgentPersona: DB layer mocked. Proves the
# per-section gold `agent_persona` knowledge_object emit (entity_ref = agent_key:section_key,
# ADR-0144 / #455 / #458), the humanized-section title, the recall facets in metadata
# (agent_key/section_key/ordinal — the containment-filter keys), the updated_by (UPN)
# exclusion, and the empty short-circuit. Mocked rows carry updated_by ON PURPOSE to prove
# the composer never serializes it.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeAgentPersona' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{
                        agent_key = 'belle'; section_key = 'identity_mandate'; ordinal = 1
                        body_md = 'You are Belle, the social engagement agent. You own the company social plane.'
                        updated_by = 'mark@imperion.example'
                    },
                    [pscustomobject]@{
                        agent_key = 'belle'; section_key = 'voice_tone'; ordinal = 6
                        body_md = 'Warm, punchy, never corporate. Short sentences.'
                        updated_by = 'mark@imperion.example'
                    },
                    [pscustomobject]@{
                        agent_key = 'dexter'; section_key = 'behavioral_guardrails'; ordinal = 9
                        body_md = 'Never bypass a containment gate. Escalate on ambiguity.'
                        updated_by = 'mark@imperion.example'
                    }
                )
            }
        }
    }

    It 'composes one gold agent_persona knowledge_object per section row, keyed agent_key:section_key' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentPersona -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 3
            $rows[0].entity_type  | Should -Be 'agent_persona'
            ($rows.entity_ref)    | Should -Be @('belle:identity_mandate', 'belle:voice_tone', 'dexter:behavioral_guardrails')
            $rows[0].source       | Should -Be 'agent_persona_section'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
        }
    }

    It 'humanizes the section key into the title and frames agent + section into the body' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentPersona -Connection ([pscustomobject]@{}))
            $section = $rows | Where-Object entity_ref -eq 'belle:identity_mandate'
            $section.title | Should -Be 'Agent persona — belle: Identity mandate'
            $section.body  | Should -Match 'Agent: belle · Section: Identity mandate'
            $section.body  | Should -Match 'You are Belle, the social engagement agent'
        }
    }

    It 'carries the recall facet keys (agent_key, section_key, ordinal) in metadata' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentPersona -Connection ([pscustomobject]@{}))
            $meta = ($rows | Where-Object entity_ref -eq 'belle:voice_tone').metadata | ConvertFrom-Json
            $meta.agent_key   | Should -Be 'belle'
            $meta.section_key | Should -Be 'voice_tone'
            $meta.ordinal     | Should -Be 6
        }
    }

    It 'never lets updated_by (an operator UPN) reach body or metadata' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentPersona -Connection ([pscustomobject]@{}))
            foreach ($row in $rows) {
                $row.body     | Should -Not -Match 'imperion\.example'
                $row.metadata | Should -Not -Match 'updated_by'
                $row.metadata | Should -Not -Match 'imperion\.example'
            }
        }
    }

    It 'returns nothing (and does not throw) when agent_persona_section has no rows' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeAgentPersona -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
