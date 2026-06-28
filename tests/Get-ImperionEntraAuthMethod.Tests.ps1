#Requires -Modules Pester
# Hermetic tests for Get-ImperionEntraAuthMethod: Graph token + requests mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionEntraAuthMethod' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'user-guid-1'; userPrincipalName = 'mark@imperionllc.com'
                        userDisplayName = 'Mark Connelly'; userType = 'member'; isAdmin = $true
                        isMfaCapable = $true; isMfaRegistered = $true
                        isPasswordlessCapable = $false
                        isSsprCapable = $true; isSsprEnabled = $true; isSsprRegistered = $false
                        isSystemPreferredAuthenticationMethodEnabled = $true
                        systemPreferredAuthenticationMethods = @('push')
                        methodsRegistered = @('microsoftAuthenticatorPush', 'softwareOneTimePasscode')
                        userPreferredMethodForSecondaryAuthentication = 'push'
                        lastUpdatedDateTime = '2026-06-12T03:00:00Z'
                    }
                    [pscustomobject]@{
                        id = 'user-guid-2'; userPrincipalName = 'nomfa@imperionllc.com'
                        userDisplayName = 'No Mfa'; userType = 'member'; isAdmin = $false
                        isMfaCapable = $false; isMfaRegistered = $false
                        methodsRegistered = @()
                    }
                )
            }
        }
    }

    It 'flattens the registration report to the 0077 columns + standard envelope' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionEntraAuthMethod)
            $rows.Count | Should -Be 2

            $registered = $rows | Where-Object { $_.external_id -eq 'user-guid-1' }
            $registered.user_principal_name | Should -Be 'mark@imperionllc.com'
            $registered.is_admin            | Should -Be 'true'
            $registered.is_mfa_capable      | Should -Be 'true'
            $registered.is_mfa_registered   | Should -Be 'true'
            $registered.is_sspr_registered  | Should -Be 'false'
            $registered.methods_registered  | Should -Be 'microsoftAuthenticatorPush; softwareOneTimePasscode'
            $registered.system_preferred_authentication_methods | Should -Be 'push'
            $registered.user_preferred_method_for_secondary_authentication | Should -Be 'push'
            $registered.source       | Should -Be 'm365'
            $registered.tenant_id    | Should -Be 'partner'
            $registered.content_hash | Should -Match '^[0-9a-f]{64}$'
            $registered.raw_payload  | Should -Match 'userRegistrationDetails|userPrincipalName'
        }
    }

    It 'keys external_id on the Entra user object id and stringifies booleans (all-text bronze)' {
        InModuleScope ImperionPipeline {
            $unregistered = @(Get-ImperionEntraAuthMethod) | Where-Object { $_.external_id -eq 'user-guid-2' }
            $unregistered.external_id       | Should -Be 'user-guid-2'
            $unregistered.is_mfa_registered | Should -Be 'false'
            $unregistered.is_mfa_registered | Should -BeOfType [string]
        }
    }

    It 'calls the userRegistrationDetails report endpoint' {
        InModuleScope ImperionPipeline {
            Get-ImperionEntraAuthMethod | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails'
            }
        }
    }

    It 'does not throw when records omit optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { @([pscustomobject]@{ id = 'bare' }) }
            { Get-ImperionEntraAuthMethod } | Should -Not -Throw
        }
    }

    It 'collects from the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionEntraAuthMethod -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
