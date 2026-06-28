#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboAccount (FULL chart of accounts).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboAccount' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens any-classification Account to the qbo_accounts shape (revenue + expense)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id = 'ACC-1'; Name = 'Sales'; FullyQualifiedName = 'Income:Sales'
                        AccountType = 'Income'; AccountSubType = 'SalesOfProductIncome'; Classification = 'Revenue'
                        CurrentBalance = 12000.00; Active = $true
                        CurrencyRef = [pscustomobject]@{ value = 'USD' }
                        MetaData = [pscustomobject]@{ CreateTime = '2026-01-01T10:00:00-00:00'; LastUpdatedTime = '2026-06-02T09:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboAccount)
            $rows.Count | Should -Be 1
            $rows[0].name | Should -Be 'Sales'
            $rows[0].account_type | Should -Be 'Income'
            $rows[0].classification | Should -Be 'Revenue'
            $rows[0].current_balance | Should -Be '12000'
            $rows[0].external_id | Should -Be 'ACC-1'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'pulls the FULL chart of accounts: NO Classification filter in the query' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboAccount | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match 'SELECT \* FROM Account' -and $Query -notmatch 'Classification' -and
                $RealmId -eq 'realm-999' -and $EntityProperty -eq 'Account'
            }
        }
    }

    It 'adds only the incremental filter when ModifiedAfter is given (still no Classification filter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboAccount -ModifiedAfter '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match "WHERE MetaData.LastUpdatedTime > '2026-06-01T00:00:00Z'" -and $Query -notmatch 'Classification'
            }
        }
    }
}
