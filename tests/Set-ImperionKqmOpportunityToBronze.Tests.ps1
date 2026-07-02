#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionKqmOpportunityToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionKqmOpportunityToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
        }
    }

    It 'projects rows to the migration-0083 kqm_opportunities column set and upserts' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                quote_number = 'Q-1001'; code = 'ABC'; title = 'Onboarding'; status = '3'; sales_order_id = '5001'
                customer_id = 'cust-9'; autotask_opportunity_id = 'ato-1'; autotask_organization_id = 'org-1'
                autotask_quote_id = 'aq-1'; contact_name = 'Jane'; contact_email = 'jane@acme.test'
                owner_employee_id = 'emp-2'; created_date = 'c'; modified_date = 'm'; expiry_date = 'e'
                tenant_id = 't1'; source = 'kqm'; external_id = '77'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionKqmOpportunityToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'kqm_opportunities'
            $captured.Rows[0].quote_number | Should -Be 'Q-1001'
            $captured.Rows[0].autotask_opportunity_id | Should -Be 'ato-1'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionKqmOpportunityToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ title = 'Q'; tenant_id = 't'; source = 'kqm'; external_id = '1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionKqmOpportunityToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
