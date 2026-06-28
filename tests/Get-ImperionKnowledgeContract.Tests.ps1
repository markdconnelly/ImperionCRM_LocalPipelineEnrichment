#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeContract: DB layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeContract' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{
                    external_id = '55'; contract_name = 'Managed Services'; contract_number = 'MS-001'
                    contract_type = '7'; contract_category = '2'; status = '1'
                    start_date = '2026-01-01'; end_date = '2027-01-01'
                    estimated_revenue = '12000'; estimated_hours = '120'
                    service_level_agreement_id = $null; description = 'Full-stack managed IT.'
                    account_name = 'Acme Corp'
                })
            }
        }
    }

    It 'composes one knowledge_object row per contract with per-entity granularity' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeContract -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 1
            $rows[0].entity_type  | Should -Be 'contract'
            $rows[0].entity_ref   | Should -Be '55'
            $rows[0].title        | Should -Be 'Managed Services'
            $rows[0].source       | Should -Be 'autotask'
            $rows[0].body         | Should -Match 'Account: Acme Corp'
            $rows[0].body         | Should -Match '2026-01-01 → 2027-01-01'
            $rows[0].body         | Should -Match 'Full-stack managed IT'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'returns nothing (and does not throw) when bronze is empty' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeContract -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
