#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboBill, including the Simple-Start graceful-degrade path.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboBill' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a Bill to the qbo_bills shape (total + balance carry the A/P signal)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id = 'BILL-2'; DocNumber = 'V-90'; TxnDate = '2026-06-01'; DueDate = '2026-06-30'
                        TotalAmt = 800.00; Balance = 800.00
                        VendorRef = [pscustomobject]@{ value = 'V-1'; name = 'Cloud Vendor' }
                        APAccountRef = [pscustomobject]@{ value = 'AP-1' }
                        CurrencyRef = [pscustomobject]@{ value = 'USD' }
                        MetaData = [pscustomobject]@{ CreateTime = '2026-06-01T10:00:00-00:00'; LastUpdatedTime = '2026-06-02T09:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboBill)
            $rows.Count | Should -Be 1
            $rows[0].doc_number | Should -Be 'V-90'
            $rows[0].total_amount | Should -Be '800'
            $rows[0].vendor_ref | Should -Be 'V-1'
            $rows[0].vendor_name | Should -Be 'Cloud Vendor'
            $rows[0].ap_account_ref | Should -Be 'AP-1'
            $rows[0].external_id | Should -Be 'BILL-2'
            $rows[0].source | Should -Be 'qbo'
        }
    }

    It 'DEGRADES GRACEFULLY when QBO returns "Feature Not Supported": warns, yields no rows' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { throw 'HTTP 400 calling GET .../query. Body: {"Fault":{"Error":[{"Message":"Feature Not Supported"}]}}' }
            $rows = @(Get-ImperionQboBill)
            $rows.Count | Should -Be 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter {
                $Level -eq 'Warn' -and $Source -eq 'qbo' -and $Message -match 'qbo_bills skipped'
            }
        }
    }

    It 're-throws any OTHER error (token expiry / transport) so the schedule fails loudly' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { throw 'HTTP 401 calling GET .../query. Body: {"Fault":{"Error":[{"Message":"AuthenticationFailed"}]}}' }
            { Get-ImperionQboBill } | Should -Throw '*401*'
            Should -Invoke Write-ImperionLog -Times 0 -ParameterFilter { $Message -match 'qbo_bills skipped' }
        }
    }

    It 'queries the Bill entity and passes the realm to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboBill | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match 'SELECT \* FROM Bill' -and $RealmId -eq 'realm-999' -and $EntityProperty -eq 'Bill'
            }
        }
    }
}
