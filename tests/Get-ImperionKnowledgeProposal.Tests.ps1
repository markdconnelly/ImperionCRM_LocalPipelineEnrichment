#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeProposal: DB layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeProposal' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{
                    id = 'prop-1'; title = 'Managed services FY27'; status = 'sent'
                    amount_mrr = '4500'; notes = 'Includes SOC monitoring add-on.'
                    sent_at = '2026-05-20'; decided_at = $null; created_at = '2026-05-15'
                    opportunity_name = 'Renewal FY27'; sales_stage = 'proposal'
                    account_name = 'Acme Corp'
                })
            }
        }
    }

    It 'composes one knowledge_object row per proposal with opportunity/account context' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeProposal -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 1
            $rows[0].entity_type  | Should -Be 'proposal'
            $rows[0].entity_ref   | Should -Be 'prop-1'
            $rows[0].title        | Should -Be 'Managed services FY27'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
            $rows[0].source       | Should -Be 'local-pipeline'
            $rows[0].body         | Should -Match 'account: Acme Corp'
            $rows[0].body         | Should -Match 'opportunity: Renewal FY27'
            $rows[0].body         | Should -Match 'status: sent'
            $rows[0].body         | Should -Match 'quoted monthly value: 4500'
            $rows[0].body         | Should -Match 'Notes: Includes SOC monitoring add-on\.'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'has the knowledge metadata shape and a stable content hash' {
        InModuleScope ImperionPipeline {
            $first  = @(Get-ImperionKnowledgeProposal -Connection ([pscustomobject]@{}))[0]
            $second = @(Get-ImperionKnowledgeProposal -Connection ([pscustomobject]@{}))[0]
            $first.content_hash | Should -Be $second.content_hash
            $metadata = $first.metadata | ConvertFrom-Json
            $metadata.account     | Should -Be 'Acme Corp'
            $metadata.opportunity | Should -Be 'Renewal FY27'
            $metadata.status      | Should -Be 'sent'
        }
    }

    It 'returns nothing (and does not throw) when there are no proposals' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeProposal -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
