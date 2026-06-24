#Requires -Modules Pester
# Hermetic unit tests for the multi-tenant credential resolver (issue #257, epic #255).
# Pins: the per-auth_method splat shape (certificate / secret / api_key), Key Vault
# resolution by the row's keyvault_secret_ref, secret material returned ONLY as a
# SecureString, the newest-active scope=client selection, and the null-vs-FailClosed
# contract on a missing row / missing material. The DB + Key Vault are mocked — no
# connection, no network, no secret ever touches disk.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionTenantCredential' {
    BeforeAll {
        $script:ACCOUNT = '11111111-1111-1111-1111-111111111111'
        $script:TENANT  = '22222222-2222-2222-2222-222222222222'
        $script:APP     = '33333333-3333-3333-3333-333333333333'
    }

    Context 'certificate auth' {
        It 'returns a ClientId + CertThumbprint + TenantId splat and never touches Key Vault' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT; t = $TENANT; app = $APP } {
                param($a, $t, $app)
                Mock Invoke-ImperionDbQuery {
                    [pscustomobject]@{ client_id = $app; auth_method = 'certificate'; keyvault_secret_ref = $null; cert_thumbprint = 'ABC123' }
                }
                Mock Get-ImperionKeyVaultSecret { throw 'should not reach Key Vault for cert auth' }

                $cred = Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'm365' -TenantId $t
                $cred.ClientId       | Should -Be $app
                $cred.CertThumbprint | Should -Be 'ABC123'
                $cred.TenantId       | Should -Be $t
                $cred.ContainsKey('ClientSecret') | Should -BeFalse
            }
        }
    }

    Context 'secret auth' {
        It 'reads Key Vault by the row ref and returns the secret ONLY as a SecureString' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT; t = $TENANT; app = $APP } {
                param($a, $t, $app)
                Mock Invoke-ImperionDbQuery {
                    [pscustomobject]@{ client_id = $app; auth_method = 'secret'; keyvault_secret_ref = 'conn-client-tenant-m365'; cert_thumbprint = $null }
                }
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'conn-client-tenant-m365') { 'super-secret' } else { throw "wrong name $Name" } }

                $cred = Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'm365' -TenantId $t
                $cred.ClientId | Should -Be $app
                $cred.TenantId | Should -Be $t
                $cred.ClientSecret | Should -BeOfType [securestring]
                # The plaintext is never a hashtable string value — only recoverable by decrypt.
                ([System.Net.NetworkCredential]::new('', $cred.ClientSecret).Password) | Should -Be 'super-secret'
                Should -Invoke Get-ImperionKeyVaultSecret -Times 1
            }
        }
    }

    Context 'api_key auth (UniFi — forward-looking)' {
        It 'returns an ApiKey splat from Key Vault' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT } {
                param($a)
                Mock Invoke-ImperionDbQuery {
                    [pscustomobject]@{ client_id = $null; auth_method = 'api_key'; keyvault_secret_ref = 'conn-client-unifi'; cert_thumbprint = $null }
                }
                Mock Get-ImperionKeyVaultSecret { 'unifi-key' }

                $cred = Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'unifi'
                $cred.ApiKey | Should -Be 'unifi-key'
            }
        }
    }

    Context 'selection query' {
        It 'selects the newest active scope=client row keyed by account + provider' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT; app = $APP } {
                param($a, $app)
                Mock Invoke-ImperionDbQuery {
                    $script:capturedSql = $Sql
                    $script:capturedParams = $Parameters
                    [pscustomobject]@{ client_id = $app; auth_method = 'certificate'; keyvault_secret_ref = $null; cert_thumbprint = 'X' }
                }
                Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'm365' | Out-Null
                $script:capturedSql | Should -Match "scope = 'client'"
                $script:capturedSql | Should -Match "status = 'active'"
                $script:capturedSql | Should -Match 'ORDER BY connected_at DESC'
                # The provider param MUST be cast to the connection_provider enum or Postgres
                # throws 42883 (no enum = text operator). Mocks can't catch this; pin the SQL (#330).
                $script:capturedSql | Should -Match 'provider = @provider::connection_provider'
                $script:capturedParams.account  | Should -Be $a
                $script:capturedParams.provider | Should -Be 'm365'
            }
        }
    }

    Context 'no usable credential' {
        It 'returns $null when no row matches' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT } {
                param($a)
                Mock Invoke-ImperionDbQuery { @() }
                Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'm365' | Should -BeNullOrEmpty
            }
        }

        It 'throws under -FailClosed when no row matches' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT } {
                param($a)
                Mock Invoke-ImperionDbQuery { @() }
                { Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'm365' -FailClosed } |
                    Should -Throw '*No active client connection*'
            }
        }

        It 'returns $null when the Key Vault secret resolves empty (no consent yet)' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT } {
                param($a)
                Mock Invoke-ImperionDbQuery {
                    [pscustomobject]@{ client_id = 'app'; auth_method = 'secret'; keyvault_secret_ref = 'ref'; cert_thumbprint = $null }
                }
                Mock Get-ImperionKeyVaultSecret { $null }
                Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'm365' | Should -BeNullOrEmpty
            }
        }

        It 'returns $null when certificate auth has no thumbprint' {
            InModuleScope ImperionPipeline -Parameters @{ a = $ACCOUNT } {
                param($a)
                Mock Invoke-ImperionDbQuery {
                    [pscustomobject]@{ client_id = 'app'; auth_method = 'certificate'; keyvault_secret_ref = $null; cert_thumbprint = $null }
                }
                Resolve-ImperionTenantCredential -Connection 'c' -AccountId $a -Provider 'm365' | Should -BeNullOrEmpty
            }
        }
    }
}
