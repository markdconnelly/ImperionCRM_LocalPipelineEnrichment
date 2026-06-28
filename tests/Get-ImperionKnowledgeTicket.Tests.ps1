#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeTicket: DB layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeTicket' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{
                    external_id = '9001'; ticket_number = 'T20260601.0042'; title = 'VPN outage'
                    status = '5'; priority = '2'; issue_type = '10'; sub_issue_type = '136'
                    ticket_type = '1'; create_date = '2026-06-01'; completed_date = '2026-06-02'
                    last_activity_date = '2026-06-02'
                    description = 'Site-to-site VPN dropped at 9am.'; resolution = 'Reprovisioned the tunnel.'
                    account_name = 'Acme Corp'
                })
            }
        }
    }

    It 'composes one knowledge_object row per ticket including description + resolution' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeTicket -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 1
            $rows[0].entity_type  | Should -Be 'ticket'
            $rows[0].entity_ref   | Should -Be '9001'
            $rows[0].title        | Should -Be '[T20260601.0042] VPN outage'
            $rows[0].body         | Should -Match 'Account: Acme Corp'
            $rows[0].body         | Should -Match 'Site-to-site VPN dropped'
            $rows[0].body         | Should -Match 'Resolution: Reprovisioned the tunnel'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'returns nothing (and does not throw) when bronze is empty' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeTicket -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
