#Requires -Modules Pester
# Hermetic tests for Get-ImperionMyItProcessRecommendation: request + key resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMyItProcessRecommendation' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Resolve-ImperionMyItProcessApiKey { 'resolved-key' }
        }
    }

    It 'flattens a recommendation to the myitprocess_recommendations envelope (external_id = id)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMyItProcessRequest {
                , @([pscustomobject]@{
                        id             = 'REC-1'
                        clientId       = 'ACC-9'
                        assessmentName = '2026 Annual Review'
                        title          = 'Adopt MFA everywhere'
                        category       = 'Security'
                        priority       = 'High'
                        status         = 'Open'
                        targetDate     = '2026-09-01'
                    })
            }
            $rows = @(Get-ImperionMyItProcessRecommendation)
            $rows.Count | Should -Be 1
            $rows[0].account_ref          | Should -Be 'ACC-9'
            $rows[0].assessment_name      | Should -Be '2026 Annual Review'
            $rows[0].recommendation_title | Should -Be 'Adopt MFA everywhere'
            $rows[0].category             | Should -Be 'Security'
            $rows[0].priority             | Should -Be 'High'
            $rows[0].status               | Should -Be 'Open'
            $rows[0].target_date          | Should -Be '2026-09-01'
            $rows[0].source               | Should -Be 'myitprocess'
            $rows[0].external_id          | Should -Be 'REC-1'
            $rows[0].content_hash         | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMyItProcessRequest { , @([pscustomobject]@{ id = 'REC-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionMyItProcessRecommendation)
            $rows[0].recommendation_title | Should -BeNullOrEmpty
            $rows[0].external_id          | Should -Be 'REC-9'
            $rows[0].raw_payload          | Should -Match 'surpriseField'
        }
    }

    It 'resolves the MSP-wide key via Resolve-ImperionMyItProcessApiKey' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMyItProcessRequest { , @() }
            Get-ImperionMyItProcessRecommendation | Out-Null
            Should -Invoke Resolve-ImperionMyItProcessApiKey -Times 1
            Should -Invoke Invoke-ImperionMyItProcessRequest -Times 1 -ParameterFilter { $ApiKey -eq 'resolved-key' }
        }
    }
}
