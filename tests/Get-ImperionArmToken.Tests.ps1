#Requires -Modules Pester
# Hermetic unit tests for the per-tenant ARM-token seam (issue #258/#327, epic #324, ADR-0030).
# Pins the uniform per-tenant credential model: EVERY tenant (Imperion/home included) authenticates
# as the onboarding app resolved from the `connection` registry — and ARM reuses the SAME m365 app
# as Graph (provider 'm365', NOT a separate 'azure' provider). No partner/home special-case and no
# config-SP fallback for a data read; an unmapped / unconsented tenant FAILS CLOSED (CLAUDE.md §3) —
# the cloud-resource sweep isolates per tenant, so a throw becomes skip + Warn there. Config, DB,
# Key Vault, MSAL are all mocked — no connection, no network, no secret on disk.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionArmToken' {
    BeforeAll {
        $script:PARTNER = '00000000-0000-0000-0000-00000000home'
        $script:CLIENT  = '22222222-2222-2222-2222-222222222222'
        $script:ACCOUNT = '11111111-1111-1111-1111-111111111111'
        $script:ARM     = 'https://management.azure.com/.default'
    }

    Context 'partner / home tenant — resolves via the registry like any tenant (ADR-0030)' {
        It 'resolves the home tenant from the registry (provider m365), never the config app' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; account = $ACCOUNT; arm = $ARM } {
                param($partner, $account, $arm)
                Mock Get-ImperionConfig { @{ ClientId = 'config-app'; PartnerTenantId = $partner } }
                Mock Get-ImperionNodeCredentialArg { throw 'a data read must not use the node bootstrap credential' }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery { [pscustomobject]@{ account_id = $account } }
                Mock Resolve-ImperionTenantCredential {
                    $script:resolveArgs = @{ Provider = $Provider; TenantId = $TenantId }
                    @{ ClientId = 'onboarding-app'; TenantId = $TenantId; CertThumbprint = 'onboarding-thumb' }
                }
                Mock Get-ImperionAccessToken { "token-for-$ClientId" }

                Get-ImperionArmToken -TenantId $partner | Should -Be 'token-for-onboarding-app'
                $script:resolveArgs.Provider | Should -Be 'm365'
                $script:resolveArgs.TenantId | Should -Be $partner
                Should -Invoke Get-ImperionAccessToken -Times 1 -ParameterFilter {
                    $ClientId -eq 'onboarding-app' -and $Resource -eq $arm
                }
            }
        }

        It 'defaults to the partner tenant when no -TenantId is given (still via the registry)' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; account = $ACCOUNT } {
                param($partner, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'config-app'; PartnerTenantId = $partner } }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery {
                    $script:tparam = $Parameters.t
                    [pscustomobject]@{ account_id = $account }
                }
                Mock Resolve-ImperionTenantCredential { @{ ClientId = 'onboarding-app'; TenantId = $TenantId; CertThumbprint = 'onboarding-thumb' } }
                Mock Get-ImperionAccessToken { "token-for-$TenantId" }

                Get-ImperionArmToken | Should -Be "token-for-$partner"
                $script:tparam | Should -Be $partner
            }
        }
    }

    Context 'managed client tenant (per-client-app model)' {
        It 'authenticates as the client own app resolved with provider m365 (ARM reuses the m365 app)' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT; account = $ACCOUNT } {
                param($partner, $client, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'config-app'; PartnerTenantId = $partner } }
                Mock Get-ImperionNodeCredentialArg { throw 'a data read must not use the node bootstrap credential' }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery { [pscustomobject]@{ account_id = $account } }
                Mock Resolve-ImperionTenantCredential {
                    $script:resolveArgs = @{ AccountId = $AccountId; Provider = $Provider; TenantId = $TenantId; FailClosed = [bool]$FailClosed }
                    @{ ClientId = 'client-app'; TenantId = $TenantId; CertThumbprint = 'client-thumb' }
                }
                Mock Get-ImperionAccessToken { "token-for-$ClientId" }

                Get-ImperionArmToken -TenantId $client | Should -Be 'token-for-client-app'
                $script:resolveArgs.Provider   | Should -Be 'm365'
                $script:resolveArgs.AccountId  | Should -Be $account
                $script:resolveArgs.TenantId   | Should -Be $client
                $script:resolveArgs.FailClosed | Should -BeTrue
                Should -Invoke Get-ImperionAccessToken -Times 1 -ParameterFilter {
                    $ClientId -eq 'client-app' -and $CertThumbprint -eq 'client-thumb'
                }
            }
        }
    }

    Context 'fail closed (CLAUDE.md §3)' {
        It 'throws when the client tenant is not mapped to an account' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT } {
                param($partner, $client)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; PartnerTenantId = $partner } }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery { @() }
                Mock Resolve-ImperionTenantCredential { throw 'must not resolve when unmapped' }
                Mock Get-ImperionAccessToken { throw 'must not mint a token when unmapped' }

                { Get-ImperionArmToken -TenantId $client } | Should -Throw '*not mapped to an account*'
            }
        }

        It 'propagates the resolver fail-closed throw when no consented credential exists' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT; account = $ACCOUNT } {
                param($partner, $client, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; PartnerTenantId = $partner } }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery { [pscustomobject]@{ account_id = $account } }
                Mock Resolve-ImperionTenantCredential { throw 'No active client connection for account ...' }
                Mock Get-ImperionAccessToken { throw 'must not mint a token without a credential' }

                { Get-ImperionArmToken -TenantId $client } | Should -Throw '*No active client connection*'
            }
        }
    }
}
