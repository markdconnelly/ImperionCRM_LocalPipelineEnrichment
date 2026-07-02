#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeAgentProcedure: DB layer mocked per query shape.
# Proves the per-definition gold `agent_procedure` knowledge_object emit (entity_ref =
# agent_key:procedure_key, ADR-0144 / #458), the goal/trigger/ordered-steps body assembly,
# the recall facets in metadata (agent_key/procedure_key/archetype/status/ceiling_level),
# the status-is-a-facet-not-a-filter contract (draft composes too), the step-less
# definition, and the empty short-circuit.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeAgentProcedure' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            # Route each of the composer's set-based queries by its FROM clause.
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM procedure_definition') {
                    return @(
                        [pscustomobject]@{
                            agent_key = 'belle'; procedure_key = 'social_triage'; procedure_ref = 'belle:social_triage'
                            name = 'Social DM triage'; business_goal = 'Every inbound DM answered within the SLA.'
                            trigger_event = 'social.dm.received'; archetype = 'triage'; status = 'active'; ceiling_level = 2
                            updated_by = 'mark@imperion.example'
                        },
                        [pscustomobject]@{
                            agent_key = 'dexter'; procedure_key = 'code_review'; procedure_ref = 'dexter:code_review'
                            name = 'Code review pass'; business_goal = $null
                            trigger_event = $null; archetype = 'review'; status = 'draft'; ceiling_level = $null
                            updated_by = 'mark@imperion.example'
                        }
                    )
                }
                if ($Sql -match 'FROM procedure_step') {
                    return @(
                        [pscustomobject]@{
                            procedure_ref = 'belle:social_triage'; step_key = 'classify'
                            name = 'Classify the DM'; description = 'Lead, support, or spam.'; actor = 'agent'; ordinal = 1
                        },
                        [pscustomobject]@{
                            procedure_ref = 'belle:social_triage'; step_key = 'draft'
                            name = 'Draft the reply'; description = 'Voice-matched draft for the gate.'; actor = 'agent'; ordinal = 2
                        }
                    )
                }
                return @()
            }
        }
    }

    It 'composes one gold agent_procedure knowledge_object per definition, keyed agent_key:procedure_key' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentProcedure -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 2
            $rows[0].entity_type  | Should -Be 'agent_procedure'
            ($rows.entity_ref)    | Should -Be @('belle:social_triage', 'dexter:code_review')
            $rows[0].source       | Should -Be 'procedure_definition'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
        }
    }

    It 'titles with the definition name and assembles goal, trigger, and the ordered steps into the body' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentProcedure -Connection ([pscustomobject]@{}))
            $procedure = $rows | Where-Object entity_ref -eq 'belle:social_triage'
            $procedure.title | Should -Be 'Social DM triage'
            $procedure.body  | Should -Match 'agent: belle · archetype: triage · status: active'
            $procedure.body  | Should -Match 'Goal: Every inbound DM answered within the SLA\.'
            $procedure.body  | Should -Match 'Trigger: social\.dm\.received'
            $procedure.body  | Should -Match 'Steps \(2\):'
            $procedure.body  | Should -Match '1\. Classify the DM \(actor: agent\) — Lead, support, or spam\.'
            $procedure.body  | Should -Match '2\. Draft the reply \(actor: agent\)'
        }
    }

    It 'carries the recall facet keys (agent_key, procedure_key, archetype, status, ceiling_level) in metadata' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentProcedure -Connection ([pscustomobject]@{}))
            $meta = ($rows | Where-Object entity_ref -eq 'belle:social_triage').metadata | ConvertFrom-Json
            $meta.agent_key     | Should -Be 'belle'
            $meta.procedure_key | Should -Be 'social_triage'
            $meta.archetype     | Should -Be 'triage'
            $meta.status        | Should -Be 'active'
            $meta.ceiling_level | Should -Be 2
            $meta.step_count    | Should -Be 2
        }
    }

    It 'composes a draft, step-less definition (status is a facet, not a filter) without a Steps section' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentProcedure -Connection ([pscustomobject]@{}))
            $procedure = $rows | Where-Object entity_ref -eq 'dexter:code_review'
            $procedure.body | Should -Match 'agent: dexter · archetype: review · status: draft'
            $procedure.body | Should -Not -Match 'Steps \('
            $procedure.body | Should -Not -Match 'Goal:'
            $meta = $procedure.metadata | ConvertFrom-Json
            $meta.status     | Should -Be 'draft'
            $meta.step_count | Should -Be 0
        }
    }

    It 'never lets updated_by (an operator UPN) reach body or metadata' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAgentProcedure -Connection ([pscustomobject]@{}))
            foreach ($row in $rows) {
                $row.body     | Should -Not -Match 'imperion\.example'
                $row.metadata | Should -Not -Match 'updated_by'
            }
        }
    }

    It 'returns nothing (and does not throw) when procedure_definition has no rows' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeAgentProcedure -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
