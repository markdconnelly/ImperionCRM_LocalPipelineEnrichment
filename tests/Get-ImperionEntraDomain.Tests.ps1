#Requires -Modules Pester
# Hermetic tests for Get-ImperionEntraDomain: Graph token + request mocked (issue #219/#142).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionEntraDomain' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'imperionllc.com'; authenticationType = 'Managed'
                        isDefault = $true; isInitial = $false; isRoot = $true; isVerified = $true
                        isAdminManaged = $true; supportedServices = @('Email', 'OfficeCommunicationsOnline')
                        passwordValidityPeriodInDays = 2147483647; passwordNotificationWindowInDays = 14
                    }
                    [pscustomobject]@{
                        id = 'imperionllc.onmicrosoft.com'; authenticationType = 'Managed'
                        isDefault = $false; isInitial = $true; isVerified = $true
                        supportedServices = @()
                    }
                )
            }
        }
    }

    It 'flattens /domains to the migration-0136 columns + standard envelope (id = the FQDN)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionEntraDomain)
            $rows.Count | Should -Be 2

            $primary = $rows | Where-Object { $_.external_id -eq 'imperionllc.com' }
            $primary.domain_name         | Should -Be 'imperionllc.com'
            $primary.authentication_type | Should -Be 'Managed'
            $primary.is_default          | Should -Be 'true'
            $primary.is_verified         | Should -Be 'true'
            $primary.supported_services  | Should -Be 'Email; OfficeCommunicationsOnline'
            $primary.source              | Should -Be 'm365'
            $primary.tenant_id           | Should -Be 'partner'
            $primary.content_hash        | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'calls the /domains endpoint' {
        InModuleScope ImperionPipeline {
            Get-ImperionEntraDomain | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/domains'
            }
        }
    }

    It 'does not throw when a domain omits optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { @([pscustomobject]@{ id = 'bare.com' }) }
            { Get-ImperionEntraDomain } | Should -Not -Throw
        }
    }

    It 'collects from the requested tenant (per-client onboarding app)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionEntraDomain -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
