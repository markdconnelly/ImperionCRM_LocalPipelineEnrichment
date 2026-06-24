#Requires -Modules Pester
# Hermetic unit tests for the DB-authoritative company credential resolver (issue #319, epic
# #318). Pins: the registry row -> keyvault_secret_ref -> Key Vault -> blob-field happy path,
# fail-closed vs null on a missing row/secret, blob extraction (and the missing-field throw via
# the real ConvertFrom-ImperionCredentialBlob), and that the local SecretStore is never touched.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionCompanyCredential' {

    BeforeEach {
        InModuleScope ImperionPipeline {
            # A disposable stand-in for the Npgsql connection so the own-connection path is
            # exercised. Built INSIDE the mock body (not captured from here) so it resolves at
            # invocation time; its Dispose bumps a module-scope counter the tests assert on.
            $script:disposeCount = 0
            Mock New-ImperionDbConnection {
                $c = [pscustomobject]@{}
                $c | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $script:disposeCount++ }
                $c
            }
            # The local SecretStore must never be consulted for a vendor secret.
            Mock Get-ImperionSecretValue { throw 'SecretStore must not be read for company credentials' }
        }
    }

    It 'follows the registry row to Key Vault and extracts the blob field' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { [pscustomobject]@{ keyvault_secret_ref = 'conn-company-itglue' } }
            Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'conn-company-itglue') { '{"apiKey":"itg-real","region":"us"}' } else { throw "wrong name $Name" } }
            Resolve-ImperionCompanyCredential -Provider 'itglue' -Field 'apiKey' | Should -Be 'itg-real'
        }
    }

    It 'selects by the DB provider enum value (televy, not LP-internal telivy)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                $Parameters['provider'] | Should -Be 'televy'
                [pscustomobject]@{ keyvault_secret_ref = 'conn-company-televy' }
            }
            Mock Get-ImperionKeyVaultSecret { '{"apiKey":"tel-real"}' }
            Resolve-ImperionCompanyCredential -Provider 'televy' -Field 'apiKey' | Should -Be 'tel-real'
        }
    }

    It 'opens and disposes its own connection when none is passed' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { [pscustomobject]@{ keyvault_secret_ref = 'conn-company-itglue' } }
            Mock Get-ImperionKeyVaultSecret { '{"apiKey":"x"}' }
            Resolve-ImperionCompanyCredential -Provider 'itglue' -Field 'apiKey' | Out-Null
            Should -Invoke New-ImperionDbConnection -Times 1
            $script:disposeCount | Should -Be 1
        }
    }

    It 'reuses a passed-in connection and does NOT open or dispose its own' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { [pscustomobject]@{ keyvault_secret_ref = 'conn-company-itglue' } }
            Mock Get-ImperionKeyVaultSecret { '{"apiKey":"x"}' }
            $caller = [pscustomobject]@{}
            $caller | Add-Member -MemberType ScriptMethod -Name Dispose -Value { throw 'must not dispose a caller-owned connection' }
            Resolve-ImperionCompanyCredential -Provider 'itglue' -Field 'apiKey' -Connection $caller | Out-Null
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    Context 'not connected (no row)' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                Mock Invoke-ImperionDbQuery { @() }
                Mock Get-ImperionKeyVaultSecret { throw 'should not reach Key Vault with no row' }
            }
        }
        It 'returns $null by default' {
            InModuleScope ImperionPipeline {
                Resolve-ImperionCompanyCredential -Provider 'apollo' -Field 'apiKey' | Should -BeNullOrEmpty
            }
        }
        It 'throws with -FailClosed' {
            InModuleScope ImperionPipeline {
                { Resolve-ImperionCompanyCredential -Provider 'apollo' -Field 'apiKey' -FailClosed } |
                    Should -Throw -ExpectedMessage "*No active company connection*apollo*"
            }
        }
    }

    It 'returns $null when the Key Vault secret resolves empty (no -FailClosed)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { [pscustomobject]@{ keyvault_secret_ref = 'conn-company-itglue' } }
            Mock Get-ImperionKeyVaultSecret { $null }
            Resolve-ImperionCompanyCredential -Provider 'itglue' -Field 'apiKey' | Should -BeNullOrEmpty
        }
    }

    It 'throws the actionable blob error when the field is missing (real ConvertFrom)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { [pscustomobject]@{ keyvault_secret_ref = 'conn-company-itglue' } }
            Mock Get-ImperionKeyVaultSecret { '{"region":"us"}' }
            { Resolve-ImperionCompanyCredential -Provider 'itglue' -Field 'apiKey' } |
                Should -Throw -ExpectedMessage "*missing the 'apiKey' field*"
        }
    }
}
