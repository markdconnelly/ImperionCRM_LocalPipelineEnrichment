#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboPayment. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboPayment' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a Payment to the qbo_payments shape (total is cash received)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id = 'PAY-3'; TxnDate = '2026-06-10'; TotalAmt = 2500.00; UnappliedAmt = 0
                        CustomerRef = [pscustomobject]@{ value = 'C-1'; name = 'Acme Co' }
                        DepositToAccountRef = [pscustomobject]@{ value = 'A-2' }
                        PaymentMethodRef = [pscustomobject]@{ value = 'M-1' }
                        CurrencyRef = [pscustomobject]@{ value = 'USD' }
                        MetaData = [pscustomobject]@{ CreateTime = '2026-06-10T10:00:00-00:00'; LastUpdatedTime = '2026-06-10T11:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboPayment)
            $rows.Count | Should -Be 1
            $rows[0].total_amount | Should -Be '2500'
            $rows[0].customer_ref | Should -Be 'C-1'
            $rows[0].deposit_account | Should -Be 'A-2'
            $rows[0].payment_method | Should -Be 'M-1'
            $rows[0].external_id | Should -Be 'PAY-3'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { , @([pscustomobject]@{ Id = 'PAY-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionQboPayment)
            $rows[0].total_amount | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'PAY-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'queries the Payment entity and passes the realm to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboPayment -ModifiedAfter '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match 'SELECT \* FROM Payment' -and
                $Query -match "MetaData.LastUpdatedTime > '2026-06-01T00:00:00Z'" -and
                $RealmId -eq 'realm-999' -and $EntityProperty -eq 'Payment'
            }
        }
    }

    It 'omits the WHERE clause for a full backfill (no ModifiedAfter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboPayment | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter { $Query -notmatch 'WHERE' }
        }
    }
}
