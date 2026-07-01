#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionKqmOpportunityDetailToBronze (4-table detail writer).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionKqmOpportunityDetailToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
        }
    }

    It 'writes each detail set to its own migration-0083 table over the shared connection' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-ImperionBronzeUpsert {
                $captured.Add([pscustomobject]@{ Table = $Table; Rows = $Rows })
                [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 }
            }
            $env = @{ tenant_id = 't'; source = 'kqm'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $detail = [pscustomobject]@{
                Sections        = @([pscustomobject]($env + @{ external_id = 'sec1'; quote_id = 'q1'; title = 'S'; stray = 'x' }))
                Lines           = @([pscustomobject]($env + @{ external_id = 'L1'; quote_section_id = 'sec1'; price = '25'; is_recurring = 'True' }))
                SalesOrders     = @([pscustomobject]($env + @{ external_id = 'so1'; quote_id = 'q1'; order_number = 'SO-1' }))
                SalesOrderLines = @([pscustomobject]($env + @{ external_id = 'OL1'; sales_order_id = 'so1'; cost = '12' }))
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }

            $tally = $detail | Set-ImperionKqmOpportunityDetailToBronze -Connection $conn

            $captured.Table | Should -Be @('kqm_opportunity_sections', 'kqm_opportunity_lines', 'kqm_sales_orders', 'kqm_sales_order_lines')
            # Sections projected to the 0083 column set (stray collector field dropped from flat).
            ($captured | Where-Object Table -eq 'kqm_opportunity_sections').Rows[0].quote_id | Should -Be 'q1'
            ($captured | Where-Object Table -eq 'kqm_opportunity_sections').Rows[0].PSObject.Properties.Name | Should -Not -Contain 'stray'
            ($captured | Where-Object Table -eq 'kqm_sales_order_lines').Rows[0].sales_order_id | Should -Be 'so1'
            $tally.sections.inserted | Should -Be 1
            $tally.salesOrderLines.inserted | Should -Be 1
        }
    }

    It 'returns four zero tallies on an empty/all-empty detail without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $detail = [pscustomobject]@{ Sections = @(); Lines = @(); SalesOrders = @(); SalesOrderLines = @() }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $detail | Set-ImperionKqmOpportunityDetailToBronze -Connection $conn
            $tally.sections.scanned | Should -Be 0
            $tally.lines.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $env = @{ tenant_id = 't'; source = 'kqm'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $detail = [pscustomobject]@{
                Sections = @([pscustomobject]($env + @{ external_id = 'sec1'; quote_id = 'q1' }))
                Lines = @(); SalesOrders = @(); SalesOrderLines = @()
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $detail | Set-ImperionKqmOpportunityDetailToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
