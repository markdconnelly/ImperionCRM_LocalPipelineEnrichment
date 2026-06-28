#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeAssessmentArtifact: DB layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeAssessmentArtifact' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{
                    id = 'art-1'; source = 'televy'; kind = 'report'; title = 'External scan — Q2'
                    dimension = 'network'; collected_at = '2026-06-01'
                    summary_gold = 'Two critical exposures on the perimeter.'; external_ref = 'tlv-77'
                    assessment_name = 'Acme security assessment'; assessment_status = 'in_progress'
                    account_name = 'Acme Corp'; televy_reports = 3
                })
            }
        }
    }

    It 'composes one knowledge_object row per artifact with assessment context' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAssessmentArtifact -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 1
            $rows[0].entity_type  | Should -Be 'assessment'
            $rows[0].entity_ref   | Should -Be 'art-1'
            $rows[0].title        | Should -Be 'External scan — Q2'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
            $rows[0].source       | Should -Be 'televy'
            $rows[0].body         | Should -Match 'assessment: Acme security assessment'
            $rows[0].body         | Should -Match 'account: Acme Corp'
            $rows[0].body         | Should -Match 'kind: report'
            $rows[0].body         | Should -Match 'scorecard dimension: network'
            $rows[0].body         | Should -Match 'Summary: Two critical exposures on the perimeter\.'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'has the knowledge metadata shape and a stable content hash' {
        InModuleScope ImperionPipeline {
            $first  = @(Get-ImperionKnowledgeAssessmentArtifact -Connection ([pscustomobject]@{}))[0]
            $second = @(Get-ImperionKnowledgeAssessmentArtifact -Connection ([pscustomobject]@{}))[0]
            $first.content_hash | Should -Be $second.content_hash
            $metadata = $first.metadata | ConvertFrom-Json
            $metadata.assessment     | Should -Be 'Acme security assessment'
            $metadata.account        | Should -Be 'Acme Corp'
            $metadata.kind           | Should -Be 'report'
            $metadata.televy_reports | Should -Be 3
        }
    }

    It 'falls back to a generated title when the artifact has none' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{
                    id = 'art-2'; source = 'm365_graph'; kind = 'snapshot'; title = $null
                    dimension = $null; collected_at = '2026-06-02'; summary_gold = $null
                    external_ref = $null; assessment_name = $null; assessment_status = $null
                    account_name = $null; televy_reports = 0
                })
            }
            $row = @(Get-ImperionKnowledgeAssessmentArtifact -Connection ([pscustomobject]@{}))[0]
            $row.title | Should -Be 'm365_graph snapshot art-2'
        }
    }

    It 'returns nothing (and does not throw) when there are no artifacts' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeAssessmentArtifact -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
