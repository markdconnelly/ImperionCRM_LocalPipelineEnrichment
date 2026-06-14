#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboBillPayment. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboBillPayment' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a BillPayment to the qbo_bill_payments shape (amount is the payment fact)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id       = 'BP-77'; TxnDate = '2026-06-05'; TotalAmt = 1480.50; PayType = 'Check'; DocNumber = 'CHK-1001'
                        VendorRef   = [pscustomobject]@{ value = 'V-9'; name = 'Contractor LLC' }
                        CurrencyRef = [pscustomobject]@{ value = 'USD' }
                        MetaData    = [pscustomobject]@{ CreateTime = '2026-06-05T10:00:00-00:00'; LastUpdatedTime = '2026-06-06T09:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboBillPayment)
            $rows.Count | Should -Be 1
            $rows[0].txn_date | Should -Be '2026-06-05'
            $rows[0].total_amount | Should -Be '1480.5'
            $rows[0].vendor_id | Should -Be 'V-9'
            $rows[0].vendor_name | Should -Be 'Contractor LLC'
            $rows[0].pay_type | Should -Be 'Check'
            $rows[0].doc_number | Should -Be 'CHK-1001'
            $rows[0].currency | Should -Be 'USD'
            $rows[0].last_updated_time | Should -Be '2026-06-06T09:00:00-00:00'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be 'BP-77'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { , @([pscustomobject]@{ Id = 'BP-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionQboBillPayment)
            $rows[0].total_amount | Should -BeNullOrEmpty
            $rows[0].vendor_id | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'BP-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'passes the MetaData.LastUpdatedTime incremental filter and the realm to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboBillPayment -ModifiedAfter '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match "MetaData.LastUpdatedTime > '2026-06-01T00:00:00Z'" -and
                $RealmId -eq 'realm-999' -and $EntityProperty -eq 'BillPayment'
            }
        }
    }

    It 'omits the WHERE clause for a full backfill (no ModifiedAfter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboBillPayment | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter { $Query -notmatch 'WHERE' }
        }
    }
}
