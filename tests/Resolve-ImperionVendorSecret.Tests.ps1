#Requires -Modules Pester
# Hermetic unit tests for the deep vendor secret resolver (issue #228) and the thin per-vendor
# adapters that delegate to it. Pins the three-tier order (explicit -> SecretStore -> Key Vault
# -> throw), the config-overridable Key Vault title, the vault-locked skip, the EXACT thrown
# message per vendor (a non-negotiable contract — callers/scheduled tasks read it), and the KQM
# outlier that returns $null instead of throwing.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionVendorSecret' {

    Context 'three-tier resolution (cdw)' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionSecretNames { @{ CdwApiKey = 'cdw-api-key' } }
            }
        }

        It 'returns an explicit -Value without touching any vault' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionSecretValue   { throw 'should not be called' }
                Mock Get-ImperionKeyVaultSecret { throw 'should not be called' }
                Resolve-ImperionVendorSecret -Vendor 'cdw' -Value 'explicit' | Should -Be 'explicit'
            }
        }

        It 'reads the SecretStore mirror when the vault is unlocked' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretValue   { if ($Name -eq 'cdw-api-key') { 'mirror' } else { throw "wrong name $Name" } }
                Mock Get-ImperionKeyVaultSecret { throw 'should not reach Key Vault' }
                Resolve-ImperionVendorSecret -Vendor 'cdw' | Should -Be 'mirror'
            }
        }

        It 'falls back to the Key Vault default title when the mirror is absent' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretValue   { $null }   # SecretStore miss
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'CDW-API-Key') { 'kv' } else { throw "wrong name $Name" } }
                Resolve-ImperionVendorSecret -Vendor 'cdw' | Should -Be 'kv'
            }
        }

        It 'honours the config-overridden Key Vault title' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretNames   { @{ CdwApiKey = 'cdw-api-key'; CdwApiKeyVaultSecret = 'Custom-CDW' } }
                Mock Get-ImperionSecretValue   { $null }
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'Custom-CDW') { 'kv2' } else { throw "wrong name $Name" } }
                Resolve-ImperionVendorSecret -Vendor 'cdw' | Should -Be 'kv2'
            }
        }

        It 'skips the SecretStore entirely when the vault is locked' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = $null
                Mock Get-ImperionSecretValue   { throw 'vault locked - should not be called' }
                Mock Get-ImperionKeyVaultSecret { 'kv-only' }
                Resolve-ImperionVendorSecret -Vendor 'cdw' | Should -Be 'kv-only'
                Should -Invoke Get-ImperionSecretValue -Times 0
            }
        }

        It 'throws the exact catalog message when nothing resolves' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretValue   { $null }
                Mock Get-ImperionKeyVaultSecret { $null }
                { Resolve-ImperionVendorSecret -Vendor 'cdw' } | Should -Throw -ExpectedMessage 'CDW API key unavailable: pass -ApiKey, provision the SecretStore secret named by CdwApiKey, or the Key Vault secret named by CdwApiKeyVaultSecret (issue #198).'
            }
        }
    }

    Context 'KQM outlier — returns $null, never throws' {
        It 'returns $null (no throw) when nothing resolves' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretNames   { @{ KqmApiKey = 'kqm-api-key' } }
                Mock Get-ImperionSecretValue   { $null }
                Mock Get-ImperionKeyVaultSecret { $null }
                { Resolve-ImperionVendorSecret -Vendor 'kqm' } | Should -Not -Throw
                Resolve-ImperionVendorSecret -Vendor 'kqm' | Should -BeNullOrEmpty
            }
        }
    }

    Context 'unknown vendor' {
        It 'throws a clear error for an unknown catalog key' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionSecretNames { @{} }
                { Resolve-ImperionVendorSecret -Vendor 'nope' } | Should -Throw -ExpectedMessage "Unknown vendor secret 'nope':*"
            }
        }
    }

    Context 'every catalog entry is well-formed' {
        It 'has the four required keys for each vendor' {
            InModuleScope ImperionPipeline {
                $catalog = Get-ImperionVendorSecretCatalog
                foreach ($vendor in $catalog.Keys) {
                    $spec = $catalog[$vendor]
                    # SecretStoreKey / VaultSecretConfigKey are OPTIONAL — KV-only entries omit
                    # them (issue #291). VaultDefault + ErrorMessage are always required.
                    $spec.Contains('VaultDefault')          | Should -BeTrue -Because "$vendor needs VaultDefault"
                    $spec.Contains('ErrorMessage')          | Should -BeTrue -Because "$vendor needs ErrorMessage (may be `$null)"
                }
            }
        }
    }
}

Describe 'per-vendor adapters delegate to the deep resolver' {

    It 'Resolve-ImperionMetaToken resolves via the meta catalog entry (-Token param preserved)' {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'vault'
            Mock Get-ImperionSecretNames   { @{ MetaSystemUserToken = 'meta-system-user-token' } }
            Mock Get-ImperionSecretValue   { if ($Name -eq 'meta-system-user-token') { 'meta-mirror' } else { throw "wrong name $Name" } }
            Mock Get-ImperionKeyVaultSecret { throw 'should not reach Key Vault' }
            Resolve-ImperionMetaToken | Should -Be 'meta-mirror'
            Resolve-ImperionMetaToken -Token 'explicit-tok' | Should -Be 'explicit-tok'
        }
    }

    It 'Resolve-ImperionMetaToken throws the exact Meta message when unresolved' {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'vault'
            Mock Get-ImperionSecretNames   { @{ MetaSystemUserToken = 'meta-system-user-token' } }
            Mock Get-ImperionSecretValue   { $null }
            Mock Get-ImperionKeyVaultSecret { $null }
            { Resolve-ImperionMetaToken } | Should -Throw -ExpectedMessage 'Meta system-user token unavailable: pass -Token, provision the SecretStore secret named by MetaSystemUserToken, or the Key Vault secret named by MetaTokenVaultSecret (ADR-0013).'
        }
    }

    It 'Resolve-ImperionCdwApiKey delegates and returns an explicit -ApiKey' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretNames   { @{ CdwApiKey = 'cdw-api-key' } }
            Mock Get-ImperionSecretValue   { throw 'should not be called' }
            Mock Get-ImperionKeyVaultSecret { throw 'should not be called' }
            Resolve-ImperionCdwApiKey -ApiKey 'explicit' | Should -Be 'explicit'
        }
    }
}
