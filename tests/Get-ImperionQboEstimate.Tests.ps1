#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboEstimate. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboEstimate' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens an Estimate to the qbo_estimates shape (txn_status is the pipeline signal)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id = 'EST-7'; DocNumber = 'Q-200'; TxnDate = '2026-05-20'; ExpirationDate = '2026-06-20'
                        TxnStatus = 'Accepted'; TotalAmt = 9000.00
                        CustomerRef = [pscustomobject]@{ value = 'C-1'; name = 'Acme Co' }
                        CurrencyRef = [pscustomobject]@{ value = 'USD' }
                        MetaData = [pscustomobject]@{ CreateTime = '2026-05-20T10:00:00-00:00'; LastUpdatedTime = '2026-05-25T09:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboEstimate)
            $rows.Count | Should -Be 1
            $rows[0].doc_number | Should -Be 'Q-200'
            $rows[0].txn_status | Should -Be 'Accepted'
            $rows[0].total_amount | Should -Be '9000'
            $rows[0].customer_ref | Should -Be 'C-1'
            $rows[0].external_id | Should -Be 'EST-7'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { , @([pscustomobject]@{ Id = 'EST-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionQboEstimate)
            $rows[0].total_amount | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'EST-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'queries the Estimate entity and passes the realm to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboEstimate | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match 'SELECT \* FROM Estimate' -and $RealmId -eq 'realm-999' -and $EntityProperty -eq 'Estimate'
            }
        }
    }
}
