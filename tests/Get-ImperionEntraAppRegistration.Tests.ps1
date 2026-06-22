#Requires -Modules Pester
# Hermetic tests for Get-ImperionEntraAppRegistration: Graph token + request mocked (issue #219/#142).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionEntraAppRegistration' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'app-obj-1'; appId = 'client-guid-1'; displayName = 'Imperion Onboarding'
                        signInAudience = 'AzureADMyOrg'; publisherDomain = 'imperionllc.com'
                        verifiedPublisher = [pscustomobject]@{ displayName = 'Imperion LLC' }
                        identifierUris = @('api://client-guid-1')
                        tags = @('internal')
                        requiredResourceAccess = @([pscustomobject]@{ resourceAppId = 'graph' }, [pscustomobject]@{ resourceAppId = 'arm' })
                        keyCredentials = @([pscustomobject]@{ endDateTime = '2027-01-01T00:00:00Z' })
                        passwordCredentials = @(
                            [pscustomobject]@{ endDateTime = '2026-09-01T00:00:00Z' }
                            # A long-past secret => earliest across key+password, already expired.
                            [pscustomobject]@{ endDateTime = '2020-01-01T00:00:00Z' }
                        )
                        createdDateTime = '2025-06-01T00:00:00Z'
                    }
                    [pscustomobject]@{
                        id = 'app-obj-2'; appId = 'client-guid-2'; displayName = 'No Creds App'
                        signInAudience = 'AzureADMyOrg'
                    }
                )
            }
        }
    }

    It 'flattens /applications to the migration-0136 columns with credential hygiene signals' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionEntraAppRegistration)
            $rows.Count | Should -Be 2

            $app = $rows | Where-Object { $_.external_id -eq 'app-obj-1' }
            $app.app_id                    | Should -Be 'client-guid-1'
            $app.display_name              | Should -Be 'Imperion Onboarding'
            $app.key_credential_count      | Should -Be '1'
            $app.password_credential_count | Should -Be '2'
            # Earliest expiry across BOTH key + password creds (the 2020 secret), and it is
            # already past -> has_expired_credential true.
            $app.earliest_credential_expiry | Should -Match '2020-01-01'
            $app.has_expired_credential     | Should -Be 'true'
            # Over-collected fields are NOT 0136 flat columns (they live in raw_payload).
            ($app.PSObject.Properties.Name -contains 'verified_publisher') | Should -BeFalse
            $app.source                    | Should -Be 'm365'
            $app.tenant_id                 | Should -Be 'partner'
        }
    }

    It 'zero-counts credentials on an app with none and reports no expiry / not expired' {
        InModuleScope ImperionPipeline {
            $bare = @(Get-ImperionEntraAppRegistration) | Where-Object { $_.external_id -eq 'app-obj-2' }
            $bare.key_credential_count       | Should -Be '0'
            $bare.password_credential_count  | Should -Be '0'
            $bare.earliest_credential_expiry | Should -BeNullOrEmpty
            $bare.has_expired_credential     | Should -Be 'false'
        }
    }

    It 'calls the /applications endpoint and honours the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionEntraAppRegistration -TenantId 'customer-9' | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/applications'
            }
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
