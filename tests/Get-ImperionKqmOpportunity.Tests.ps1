#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionKqmOpportunity. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKqmOpportunity' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ KqmApiKey = 'kqm-api-key'; KqmApiKeyVaultSecret = 'KQM-API-Key' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a won quote header to the verified kqm_opportunities shape (status int, autotask FKs, no total)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest {
                , @([pscustomobject]@{
                        id = 77; quoteNumber = 'Q-1001'; code = 'ABC'; title = 'Onboarding bundle'
                        status = 3; salesOrderId = 5001; customerID = 'cust-9'
                        autotaskOpportunityID = 'ato-1'; autotaskOrganizationID = 'org-1'; autotaskQuoteID = 'aq-1'
                        contactName = 'Jane'; contactEmail = 'jane@acme.test'; ownerEmployeeID = 'emp-2'
                        createdDate = '2026-05-01'; modifiedDate = '2026-06-01'; expiryDate = '2026-07-01'
                    })
            }
            $rows = @(Get-ImperionKqmOpportunity -ApiKey 'k')
            $rows.Count | Should -Be 1
            $rows[0].quote_number | Should -Be 'Q-1001'
            $rows[0].title | Should -Be 'Onboarding bundle'
            $rows[0].status | Should -Be '3'                       # int enum coerced to text
            $rows[0].sales_order_id | Should -Be '5001'            # present => won
            $rows[0].autotask_opportunity_id | Should -Be 'ato-1'  # the sale->delivery seam
            $rows[0].autotask_organization_id | Should -Be 'org-1'
            $rows[0].autotask_quote_id | Should -Be 'aq-1'
            $rows[0].customer_id | Should -Be 'cust-9'
            $rows[0].contact_email | Should -Be 'jane@acme.test'
            $rows[0].PSObject.Properties.Name | Should -Not -Contain 'total'
            $rows[0].source | Should -Be 'kqm'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be '77'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
            $rows[0].raw_payload | Should -Match 'Onboarding bundle'
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest { , @([pscustomobject]@{ id = 9; surpriseField = 'x' }) }
            $rows = @(Get-ImperionKqmOpportunity -ApiKey 'k')
            $rows[0].title | Should -BeNullOrEmpty
            $rows[0].autotask_opportunity_id | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be '9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'passes the modifiedAfter filter and never puts the key in the URI it builds' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest { @() }
            Get-ImperionKqmOpportunity -ApiKey 'sekret' -ModifiedAfter '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionKqmRequest -Times 1 -ParameterFilter {
                $Uri -match 'modifiedAfter=2026-06-01T00%3A00%3A00Z' -and $Uri -notmatch 'sekret' -and $ApiKey -eq 'sekret'
            }
        }
    }

    It 'resolves the key by following the registry row to conn-company-quotemanager (epic #318)' {
        InModuleScope ImperionPipeline {
            Mock New-ImperionDbConnection {
                $c = [pscustomobject]@{}
                $c | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
                $c
            }
            Mock Invoke-ImperionDbQuery { [pscustomobject]@{ keyvault_secret_ref = 'conn-company-quotemanager' } }
            Mock Get-ImperionKeyVaultSecret { 'kv-value' }
            Mock Invoke-ImperionKqmRequest { @() }
            Get-ImperionKqmOpportunity | Out-Null
            Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'conn-company-quotemanager' }
            Should -Invoke Invoke-ImperionKqmRequest -Times 1 -ParameterFilter { $ApiKey -eq 'kv-value' }
        }
    }
}
