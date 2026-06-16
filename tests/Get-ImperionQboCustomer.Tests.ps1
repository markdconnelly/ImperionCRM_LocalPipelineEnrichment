#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboCustomer. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboCustomer' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a Customer to the qbo_customers shape (display_name is the join hint)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest {
                , @([pscustomobject]@{
                        Id = 'C-1'; DisplayName = 'Acme Co'; CompanyName = 'Acme Corporation'; Active = $true; Balance = 2500.00
                        PrimaryEmailAddr = [pscustomobject]@{ Address = 'ap@acme.example' }
                        PrimaryPhone = [pscustomobject]@{ FreeFormNumber = '555-0100' }
                        CurrencyRef = [pscustomobject]@{ value = 'USD' }
                        MetaData = [pscustomobject]@{ CreateTime = '2026-01-01T10:00:00-00:00'; LastUpdatedTime = '2026-06-02T09:00:00-00:00' }
                    })
            }
            $rows = @(Get-ImperionQboCustomer)
            $rows.Count | Should -Be 1
            $rows[0].display_name | Should -Be 'Acme Co'
            $rows[0].company_name | Should -Be 'Acme Corporation'
            $rows[0].active | Should -Be 'True'
            $rows[0].balance | Should -Be '2500'
            $rows[0].primary_email | Should -Be 'ap@acme.example'
            $rows[0].primary_phone | Should -Be '555-0100'
            $rows[0].external_id | Should -Be 'C-1'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { , @([pscustomobject]@{ Id = 'C-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionQboCustomer)
            $rows[0].display_name | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'C-9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'queries the Customer entity and passes the realm to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionQboRequest { @() }
            Get-ImperionQboCustomer | Out-Null
            Should -Invoke Invoke-ImperionQboRequest -Times 1 -ParameterFilter {
                $Query -match 'SELECT \* FROM Customer' -and $RealmId -eq 'realm-999' -and $EntityProperty -eq 'Customer'
            }
        }
    }
}
