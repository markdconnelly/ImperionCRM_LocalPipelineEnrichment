#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeAccount: DB layer mocked per query shape.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeAccount' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            # Route each of the composer's set-based queries by its FROM clause.
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM account a') {
                    return @([pscustomobject]@{ id = 'acc-1'; name = 'Acme Corp'; relationship = 'customer'; lifecycle_stage = 'active'; health_score = '82' })
                }
                if ($Sql -match 'FROM contact c') {
                    return @([pscustomobject]@{ account_id = 'acc-1'; full_name = 'Jane Doe'; title = 'IT Director'; email = 'jane@acme.com'; crm_stage = 'client' })
                }
                if ($Sql -match 'FROM opportunity') {
                    return @([pscustomobject]@{ account_id = 'acc-1'; name = 'Renewal FY27'; sales_stage = 'proposal' })
                }
                if ($Sql -match 'FROM autotask_contracts') {
                    return @([pscustomobject]@{ account_id = 'acc-1'; contract_name = 'Managed Services'; status = '1'; start_date = '2026-01-01'; end_date = '2027-01-01' })
                }
                if ($Sql -match 'FROM autotask_tickets') {
                    return @([pscustomobject]@{ account_id = 'acc-1'; ticket_number = 'T0042'; title = 'VPN outage'; status = '5'; last_activity_date = '2026-06-01' })
                }
                return @()
            }
        }
    }

    It 'composes one knowledge_object row per account with the gold envelope' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeAccount -Connection ([pscustomobject]@{}))
            $rows.Count            | Should -Be 1
            $rows[0].entity_type   | Should -Be 'account'
            $rows[0].entity_ref    | Should -Be 'acc-1'
            $rows[0].title         | Should -Be 'Acme Corp'
            $rows[0].tenant_id     | Should -Be 'tenant-1'
            $rows[0].source        | Should -Be 'local-pipeline'
            $rows[0].content_hash  | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'writes the contacts, opportunities, contracts, and tickets into the body text' {
        InModuleScope ImperionPipeline {
            $row = @(Get-ImperionKnowledgeAccount -Connection ([pscustomobject]@{}))[0]
            $row.body | Should -Match 'Account: Acme Corp'
            $row.body | Should -Match 'Jane Doe'
            $row.body | Should -Match 'Renewal FY27'
            $row.body | Should -Match 'Managed Services'
            $row.body | Should -Match 'VPN outage'
        }
    }

    It 'produces a stable content hash for unchanged data (idempotency key)' {
        InModuleScope ImperionPipeline {
            $first  = @(Get-ImperionKnowledgeAccount -Connection ([pscustomobject]@{}))[0].content_hash
            $second = @(Get-ImperionKnowledgeAccount -Connection ([pscustomobject]@{}))[0].content_hash
            $first | Should -Be $second
        }
    }

    It 'returns nothing (and does not throw) when there are no accounts' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeAccount -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
