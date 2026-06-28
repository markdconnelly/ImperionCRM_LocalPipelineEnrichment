#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboInvoice. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboInvoice' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens an Invoice to the qbo_invoices shape (total + balance carry the A/R signal)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id = 'INV-5'; DocNumber = '1042'; TxnDate = '2026-06-01'; DueDate = '2026-07-01'
                        TotalAmt = 2500.00; Balance = 2500.00
                        CustomerRef = [pscustomobject]@{ value = 'C-1'; name = 'Acme Co' }
                        CurrencyRef = [pscustomobject]@{ value = 'USD' }
                        MetaData = [pscustomobject]@{ CreateTime = '2026-06-01T10:00:00-00:00'; LastUpdatedTime = '2026-06-02T09:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboInvoice)
            $rows.Count | Should -Be 1
            $rows[0].doc_number | Should -Be '1042'
            $rows[0].total_amount | Should -Be '2500'
            $rows[0].balance | Should -Be '2500'
            $rows[0].customer_ref | Should -Be 'C-1'
            $rows[0].customer_name | Should -Be 'Acme Co'
            $rows[0].currency | Should -Be 'USD'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be 'INV-5'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { , @([pscustomobject]@{ Id = 'INV-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionQboInvoice)
            $rows[0].total_amount | Should -BeNullOrEmpty
            $rows[0].customer_ref | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'INV-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'queries the Invoice entity, passes the incremental filter and the realm to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboInvoice -ModifiedAfter '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match 'SELECT \* FROM Invoice' -and
                $Query -match "MetaData.LastUpdatedTime > '2026-06-01T00:00:00Z'" -and
                $RealmId -eq 'realm-999' -and $EntityProperty -eq 'Invoice'
            }
        }
    }

    It 'omits the WHERE clause for a full backfill (no ModifiedAfter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboInvoice | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter { $Query -notmatch 'WHERE' }
        }
    }
}
