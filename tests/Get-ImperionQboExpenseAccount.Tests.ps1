#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboExpenseAccount. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboExpenseAccount' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens an expense Account to the qbo_expense_account shape' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id = 'ACC-42'; Name = 'Travel'; FullyQualifiedName = 'Expenses:Travel'
                        AccountType = 'Expense'; AccountSubType = 'Travel'; Classification = 'Expense'; Active = $true
                        MetaData = [pscustomobject]@{ CreateTime = '2026-01-02T10:00:00-00:00'; LastUpdatedTime = '2026-06-06T09:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboExpenseAccount)
            $rows.Count | Should -Be 1
            $rows[0].name | Should -Be 'Travel'
            $rows[0].fully_qualified_name | Should -Be 'Expenses:Travel'
            $rows[0].account_type | Should -Be 'Expense'
            $rows[0].account_sub_type | Should -Be 'Travel'
            $rows[0].classification | Should -Be 'Expense'
            $rows[0].active | Should -Be 'True'
            $rows[0].last_updated_time | Should -Be '2026-06-06T09:00:00-00:00'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be 'ACC-42'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { , @([pscustomobject]@{ Id = 'ACC-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionQboExpenseAccount)
            $rows[0].name | Should -BeNullOrEmpty
            $rows[0].account_type | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'ACC-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'requests only expense-classification accounts and passes the realm to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboExpenseAccount | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match "FROM Account WHERE Classification = 'Expense'" -and
                $RealmId -eq 'realm-999' -and $EntityProperty -eq 'Account'
            }
        }
    }

    It 'adds the MetaData.LastUpdatedTime incremental filter when ModifiedAfter is given' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboExpenseAccount -ModifiedAfter '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match "Classification = 'Expense' AND MetaData.LastUpdatedTime > '2026-06-01T00:00:00Z'"
            }
        }
    }

    It 'omits the incremental clause for a full backfill (no ModifiedAfter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboExpenseAccount | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter { $Query -notmatch 'LastUpdatedTime' }
        }
    }
}
