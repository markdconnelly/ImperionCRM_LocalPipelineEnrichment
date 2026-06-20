#Requires -Modules Pester
# Hermetic unit tests for the per-tenant ARM-token seam (issue #258, epic #255, ADR-0028).
# Pins the per-client-app credential model for Azure ARM: a managed CLIENT tenant authenticates
# as THAT client's own app (resolved from the `connection` registry, provider 'azure'), never
# the shared home app; the partner/home tenant keeps the home enterprise-app cred and never
# touches the DB; an unmapped / unconsented client tenant FAILS CLOSED (CLAUDE.md §3) — the
# cloud-resource sweep isolates per tenant, so a throw becomes skip + Warn there. Config, DB,
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

    Context 'home / partner tenant' {
        It 'uses the shared home enterprise-app credential and never touches the registry' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; arm = $ARM } {
                param($partner, $arm)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; PartnerTenantId = $partner } }
                Mock Get-ImperionAppCredentialArg { @{ CertThumbprint = 'home-thumb' } }
                Mock New-ImperionDbConnection { throw 'home path must not open a DB connection' }
                Mock Resolve-ImperionTenantCredential { throw 'home path must not resolve a client credential' }
                Mock Get-ImperionAccessToken { "token-for-$ClientId" }

                Get-ImperionArmToken -TenantId $partner | Should -Be 'token-for-home-app'
                Should -Invoke Get-ImperionAccessToken -Times 1 -ParameterFilter {
                    $ClientId -eq 'home-app' -and $TenantId -eq $partner -and $Resource -eq $arm
                }
                Should -Invoke New-ImperionDbConnection -Times 0
            }
        }

        It 'defaults to the partner tenant with the home credential when no -TenantId is given' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER } {
                param($partner)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; PartnerTenantId = $partner } }
                Mock Get-ImperionAppCredentialArg { @{ CertThumbprint = 'home-thumb' } }
                Mock New-ImperionDbConnection { throw 'home path must not open a DB connection' }
                Mock Get-ImperionAccessToken { "token-for-$TenantId" }

                Get-ImperionArmToken | Should -Be "token-for-$partner"
            }
        }
    }

    Context 'managed client tenant (per-client-app model)' {
        It 'authenticates as the client own app resolved with provider azure, not the home app' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT; account = $ACCOUNT } {
                param($partner, $client, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; PartnerTenantId = $partner } }
                Mock Get-ImperionAppCredentialArg { throw 'client path must not use the home credential' }
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
                $script:resolveArgs.Provider   | Should -Be 'azure'
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

        It 'propagates the resolver fail-closed throw when no consented azure credential exists' {
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
