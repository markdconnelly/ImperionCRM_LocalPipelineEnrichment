#Requires -Modules Pester
# Hermetic unit tests for the per-tenant Graph-token seam (issue #250/#327, epic #324, ADR-0030).
# Pins the uniform per-tenant credential model: EVERY tenant (Imperion/home included) authenticates
# as the onboarding app resolved from the `connection` registry via account_tenant (provider
# 'm365', cert OR secret) — there is no partner/home special-case and the config SP is never used
# for a data read; an unmapped / unconsented tenant FAILS CLOSED (CLAUDE.md §3).
# Config, DB, Key Vault, MSAL are all mocked — no connection, no network, no secret on disk.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionGraphToken' {
    BeforeAll {
        $script:PARTNER = '00000000-0000-0000-0000-00000000home'
        $script:CLIENT  = '22222222-2222-2222-2222-222222222222'
        $script:ACCOUNT = '11111111-1111-1111-1111-111111111111'
    }

    Context 'partner / home tenant — resolves via the registry like any tenant (ADR-0030)' {
        It 'resolves the home tenant from the registry (provider m365), never the config app' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; account = $ACCOUNT } {
                param($partner, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'config-app'; LocalTenantId = $partner } }
                Mock Get-ImperionNodeCredentialArg { throw 'a data read must not use the node bootstrap credential' }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery {
                    $script:tparam = $Parameters.t
                    [pscustomobject]@{ account_id = $account }
                }
                Mock Resolve-ImperionTenantCredential {
                    $script:resolveArgs = @{ Provider = $Provider; TenantId = $TenantId }
                    @{ ClientId = 'onboarding-app'; TenantId = $TenantId; CertThumbprint = 'onboarding-thumb' }
                }
                Mock Get-ImperionAccessToken { "token-for-$ClientId" }

                $tok = Get-ImperionGraphToken -TenantId $partner
                $tok | Should -Be 'token-for-onboarding-app'
                $script:resolveArgs.Provider | Should -Be 'm365'
                $script:resolveArgs.TenantId | Should -Be $partner
                $script:tparam | Should -Be $partner
                Should -Invoke Get-ImperionAccessToken -Times 1 -ParameterFilter {
                    $ClientId -eq 'onboarding-app' -and $Resource -eq 'https://graph.microsoft.com/.default'
                }
            }
        }

        It 'defaults to the partner tenant when no -TenantId is given (still via the registry)' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; account = $ACCOUNT } {
                param($partner, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'config-app'; LocalTenantId = $partner } }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery {
                    $script:tparam = $Parameters.t
                    [pscustomobject]@{ account_id = $account }
                }
                Mock Resolve-ImperionTenantCredential { @{ ClientId = 'onboarding-app'; TenantId = $TenantId; CertThumbprint = 'onboarding-thumb' } }
                Mock Get-ImperionAccessToken { "token-for-$TenantId" }

                Get-ImperionGraphToken | Should -Be "token-for-$partner"
                $script:tparam | Should -Be $partner
            }
        }
    }

    Context 'managed client tenant (per-client-app model)' {
        It 'authenticates as the client own app resolved from the registry, not the home app' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT; account = $ACCOUNT } {
                param($partner, $client, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; LocalTenantId = $partner } }
                Mock Get-ImperionNodeCredentialArg { throw 'a data read must not use the node bootstrap credential' }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery {
                    $script:capturedSql = $Sql; $script:capturedParams = $Parameters
                    [pscustomobject]@{ account_id = $account }
                }
                Mock Resolve-ImperionTenantCredential {
                    $script:resolveArgs = @{ AccountId = $AccountId; Provider = $Provider; TenantId = $TenantId; FailClosed = [bool]$FailClosed }
                    @{ ClientId = 'client-app'; TenantId = $TenantId; CertThumbprint = 'client-thumb' }
                }
                Mock Get-ImperionAccessToken { "token-for-$ClientId" }

                $tok = Get-ImperionGraphToken -TenantId $client
                $tok | Should -Be 'token-for-client-app'

                # Resolved by the owning account, m365 provider, fail-closed.
                $script:resolveArgs.AccountId  | Should -Be $account
                $script:resolveArgs.Provider   | Should -Be 'm365'
                $script:resolveArgs.TenantId   | Should -Be $client
                $script:resolveArgs.FailClosed | Should -BeTrue
                # Account looked up from account_tenant by the client tenant id.
                $script:capturedSql | Should -Match 'account_tenant'
                # account_tenant.tenant_id is a TEXT column; casting the param to uuid throws
                # 42883 (text = uuid). The lookup must compare text-to-text, no ::uuid. #334
                $script:capturedSql | Should -Match 'tenant_id = @t\b'
                $script:capturedSql | Should -Not -Match 'tenant_id = @t::uuid'
                $script:capturedParams.t | Should -Be $client
                # Minted with the CLIENT app id + the resolved cert, never the home app.
                Should -Invoke Get-ImperionAccessToken -Times 1 -ParameterFilter {
                    $ClientId -eq 'client-app' -and $CertThumbprint -eq 'client-thumb'
                }
            }
        }

        It 'reuses a caller-supplied connection instead of opening its own' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT; account = $ACCOUNT } {
                param($partner, $client, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; LocalTenantId = $partner } }
                Mock New-ImperionDbConnection { throw 'must not open its own connection when one is supplied' }
                Mock Invoke-ImperionDbQuery { [pscustomobject]@{ account_id = $account } }
                Mock Resolve-ImperionTenantCredential { @{ ClientId = 'client-app'; TenantId = $TenantId; CertThumbprint = 'c' } }
                Mock Get-ImperionAccessToken { 'ok' }

                Get-ImperionGraphToken -TenantId $client -Connection 'borrowed' | Should -Be 'ok'
                Should -Invoke New-ImperionDbConnection -Times 0
            }
        }
    }

    Context 'fail closed (CLAUDE.md §3)' {
        It 'throws when the client tenant is not mapped to an account' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT } {
                param($partner, $client)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; LocalTenantId = $partner } }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery { @() }
                Mock Resolve-ImperionTenantCredential { throw 'must not resolve when unmapped' }
                Mock Get-ImperionAccessToken { throw 'must not mint a token when unmapped' }

                { Get-ImperionGraphToken -TenantId $client } | Should -Throw '*not mapped to an account*'
            }
        }

        It 'propagates the resolver fail-closed throw when no consented credential exists' {
            InModuleScope ImperionPipeline -Parameters @{ partner = $PARTNER; client = $CLIENT; account = $ACCOUNT } {
                param($partner, $client, $account)
                Mock Get-ImperionConfig { @{ ClientId = 'home-app'; LocalTenantId = $partner } }
                $fakeConn = [pscustomobject]@{}
                $fakeConn | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                Mock New-ImperionDbConnection { $fakeConn }
                Mock Invoke-ImperionDbQuery { [pscustomobject]@{ account_id = $account } }
                Mock Resolve-ImperionTenantCredential { throw 'No active client connection for account ...' }
                Mock Get-ImperionAccessToken { throw 'must not mint a token without a credential' }

                { Get-ImperionGraphToken -TenantId $client } | Should -Throw '*No active client connection*'
            }
        }
    }
}
