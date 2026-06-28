#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionKqmOpportunityDetail. Connect layer + context mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKqmOpportunityDetail' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ KqmApiKey = 'kqm-api-key'; KqmApiKeyVaultSecret = 'KQM-API-Key' } }
            Mock Write-ImperionLog { }
            # Per-endpoint detail collections; only the won-quote (q1) chain should survive.
            Mock Invoke-ImperionKqmRequest -ParameterFilter { $Uri -match '/quotesection' } {
                @(
                    [pscustomobject]@{ id = 'sec1'; quoteID = 'q1'; type = 'standard'; lineNumber = 1; isMultiChoice = $false; isSelected = $true; title = 'Managed services' }
                    [pscustomobject]@{ id = 'sec2'; quoteID = 'qX'; type = 'standard'; title = 'Not won' }
                )
            }
            Mock Invoke-ImperionKqmRequest -ParameterFilter { $Uri -match '/quoteline' } {
                @(
                    [pscustomobject]@{ id = 'L1'; quoteSectionID = 'sec1'; productID = 'p1'; title = 'Endpoint protection'; price = 25; quantity = 10; isOptional = $false; isSelected = $true; isRecurring = $true; recurringType = 'monthly' }
                    [pscustomobject]@{ id = 'L2'; quoteSectionID = 'sec2'; title = 'Dropped line' }
                )
            }
            Mock Invoke-ImperionKqmRequest -ParameterFilter { $Uri -match '/salesorder$|/salesorder\?' } {
                @(
                    [pscustomobject]@{ id = 'so1'; quoteID = 'q1'; orderNumber = 'SO-1'; status = 'open'; customerID = 'cust-9' }
                    [pscustomobject]@{ id = 'so2'; quoteID = 'qX'; orderNumber = 'SO-X' }
                )
            }
            Mock Invoke-ImperionKqmRequest -ParameterFilter { $Uri -match '/salesorderline' } {
                @(
                    [pscustomobject]@{ id = 'OL1'; salesOrderID = 'so1'; productID = 'p1'; cost = 12; price = 25; quantity = 10; isRecurring = $true }
                    [pscustomobject]@{ id = 'OL2'; salesOrderID = 'soX'; title = 'Dropped order line' }
                )
            }
        }
    }

    It 'returns empty sets and makes no API call when no won quotes are passed' {
        InModuleScope ImperionPipeline {
            $detail = Get-ImperionKqmOpportunityDetail -WonQuoteId @() -ApiKey 'k'
            $detail.Sections.Count | Should -Be 0
            $detail.Lines.Count | Should -Be 0
            $detail.SalesOrders.Count | Should -Be 0
            $detail.SalesOrderLines.Count | Should -Be 0
            Should -Invoke Invoke-ImperionKqmRequest -Times 0
        }
    }

    It 'keeps only detail belonging to the won quote across the full join chain' {
        InModuleScope ImperionPipeline {
            $detail = Get-ImperionKqmOpportunityDetail -WonQuoteId @('q1') -ApiKey 'k'

            $detail.Sections.Count | Should -Be 1
            $detail.Sections[0].external_id | Should -Be 'sec1'
            $detail.Sections[0].quote_id | Should -Be 'q1'

            $detail.Lines.Count | Should -Be 1          # L2 dropped (section sec2 is not won)
            $detail.Lines[0].external_id | Should -Be 'L1'
            $detail.Lines[0].quote_section_id | Should -Be 'sec1'
            $detail.Lines[0].is_recurring | Should -Be 'True'   # text-coerced; MRR split happens in silver
            $detail.Lines[0].price | Should -Be '25'

            $detail.SalesOrders.Count | Should -Be 1
            $detail.SalesOrders[0].external_id | Should -Be 'so1'

            $detail.SalesOrderLines.Count | Should -Be 1 # OL2 dropped (order soX is not won)
            $detail.SalesOrderLines[0].external_id | Should -Be 'OL1'
            $detail.SalesOrderLines[0].sales_order_id | Should -Be 'so1'
        }
    }

    It 'stamps the standard envelope and keeps the lossless payload on every detail row' {
        InModuleScope ImperionPipeline {
            $detail = Get-ImperionKqmOpportunityDetail -WonQuoteId @('q1') -ApiKey 'k'
            foreach ($row in @($detail.Sections) + @($detail.Lines) + @($detail.SalesOrders) + @($detail.SalesOrderLines)) {
                $row.source | Should -Be 'kqm'
                $row.tenant_id | Should -Be 'partner-tenant'
                $row.content_hash | Should -Not -BeNullOrEmpty
                $row.raw_payload | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'never puts the api key in a detail request URI it builds' {
        InModuleScope ImperionPipeline {
            Get-ImperionKqmOpportunityDetail -WonQuoteId @('q1') -ApiKey 'sekret' | Out-Null
            Should -Invoke Invoke-ImperionKqmRequest -ParameterFilter { $Uri -notmatch 'sekret' -and $ApiKey -eq 'sekret' }
        }
    }
}
