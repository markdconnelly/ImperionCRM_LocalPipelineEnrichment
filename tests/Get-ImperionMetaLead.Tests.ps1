#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaLeadForm + Get-ImperionMetaLead (LP #362).
# Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaLeadForm' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a lead form to the meta_lead_ad_forms shape (source=meta_lead_ad), questions as json' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{
                        id           = 'form_1'
                        name         = 'Contact us'
                        status       = 'ACTIVE'
                        locale       = 'en_US'
                        questions    = @([pscustomobject]@{ key = 'email'; label = 'Email' })
                        leads_count  = 12
                        created_time = '2026-06-01T12:00:00+0000'
                    })
            }
            $rows = @(Get-ImperionMetaLeadForm -PageId '123' -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].page_id | Should -Be '123'
            $rows[0].form_name | Should -Be 'Contact us'
            $rows[0].status | Should -Be 'ACTIVE'
            $rows[0].leads_count | Should -Be '12'
            $rows[0].questions | Should -Match 'email'
            $rows[0].source | Should -Be 'meta_lead_ad'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be 'form_1'
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -match '^123/leadgen_forms\?fields=' }
        }
    }
}

Describe 'Get-ImperionMetaLead' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'takes form rows from the pipeline, fans /leads per form, and extracts field_data answers' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{
                        id            = 'lead_1'
                        created_time  = '2026-06-03T09:00:00+0000'
                        ad_id         = 'ad_9'
                        campaign_id   = 'camp_1'
                        platform      = 'fb'
                        field_data    = @(
                            [pscustomobject]@{ name = 'full_name'; values = @('Jane Doe') }
                            [pscustomobject]@{ name = 'email'; values = @('jane@example.com') }
                            [pscustomobject]@{ name = 'phone_number'; values = @('+15551234567') }
                        )
                    })
            }
            $formRow = [pscustomobject]@{ external_id = 'form_1' }
            $rows = @($formRow | Get-ImperionMetaLead -PageId '123' -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].form_id | Should -Be 'form_1'
            $rows[0].page_id | Should -Be '123'
            $rows[0].ad_id | Should -Be 'ad_9'
            $rows[0].full_name | Should -Be 'Jane Doe'
            $rows[0].email | Should -Be 'jane@example.com'
            $rows[0].phone_number | Should -Be '+15551234567'
            $rows[0].field_data | Should -Match 'jane@example.com'
            $rows[0].source | Should -Be 'meta_lead_ad'
            $rows[0].external_id | Should -Be 'lead_1'
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -match '^form_1/leads\?fields=' }
        }
    }

    It 'fans an explicit -FormId array, one /leads call per form' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionMetaLead -FormId 'a', 'b' -Token 't' | Out-Null
            Should -Invoke Invoke-ImperionMetaRequest -Times 2
        }
    }
}
