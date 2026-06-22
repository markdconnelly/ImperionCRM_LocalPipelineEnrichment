#Requires -Modules Pester
# Hermetic unit tests for the three private RMM/managed-estate key resolvers (issue #195, ADR-0018):
# Resolve-ImperionDattoRmmApiKey / Resolve-ImperionDattoBcdrApiKey / Resolve-ImperionMyItProcessApiKey.
# Resolution order (explicit -> SecretStore mirror -> Key Vault original) + fail-loud when unavailable.
# No secret VALUES anywhere — only stable secret NAMES.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'RMM/managed-estate key resolvers' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretNames {
                @{
                    DattoRmmApiKey = 'datto-rmm-api-key'; DattoRmmApiKeyVaultSecret = 'Datto-RMM-API-Key'
                    DattoBcdrApiKey = 'datto-bcdr-api-key'; DattoBcdrApiKeyVaultSecret = 'Datto-BCDR-API-Key'
                    MyItProcessApiKey = 'myitprocess-api-key'; MyItProcessApiKeyVaultSecret = 'myITprocess-API-Key'
                }
            }
            $script:ImperionSecretStoreVault = $null
        }
    }

    Context 'Resolve-ImperionDattoRmmApiKey' {
        It 'returns an explicit -ApiKey without touching any vault' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionSecretValue { throw 'should not be called' }
                Mock Get-ImperionKeyVaultSecret { throw 'should not be called' }
                Resolve-ImperionDattoRmmApiKey -ApiKey 'explicit' | Should -Be 'explicit'
            }
        }
        It 'reads the SecretStore mirror when the vault is unlocked' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretValue { if ($Name -eq 'datto-rmm-api-key') { 'mirror-key' } }
                Mock Get-ImperionKeyVaultSecret { throw 'should not reach Key Vault' }
                Resolve-ImperionDattoRmmApiKey | Should -Be 'mirror-key'
            }
        }
        It 'falls back to the Key Vault original when the mirror is absent' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretValue { $null }
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'Datto-RMM-API-Key') { 'kv-key' } }
                Resolve-ImperionDattoRmmApiKey | Should -Be 'kv-key'
            }
        }
        It 'throws (fail loud) when no key is available' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { $null }
                { Resolve-ImperionDattoRmmApiKey } | Should -Throw '*Datto RMM API key unavailable*'
            }
        }
    }

    Context 'Resolve-ImperionDattoBcdrApiKey' {
        It 'falls back to the Key Vault original when the mirror is absent' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretValue { $null }
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'Datto-BCDR-API-Key') { 'kv-key' } }
                Resolve-ImperionDattoBcdrApiKey | Should -Be 'kv-key'
            }
        }
        It 'throws (fail loud) when no key is available' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { $null }
                { Resolve-ImperionDattoBcdrApiKey } | Should -Throw '*Datto BCDR API key unavailable*'
            }
        }
    }

    Context 'Resolve-ImperionMyItProcessApiKey (rerouted to conn-company blob, #292/#299)' {
        It 'extracts apiKey from the conn-company-myitprocess JSON blob (NOT the legacy name)' {
            InModuleScope ImperionPipeline {
                $script:ImperionSecretStoreVault = 'vault'
                Mock Get-ImperionSecretValue { throw 'myITprocess is KV-only now — the SecretStore mirror must not be read' }
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'conn-company-myitprocess') { '{"apiKey":"kv-key"}' } else { throw "wrong name $Name" } }
                Resolve-ImperionMyItProcessApiKey | Should -Be 'kv-key'
            }
        }
        It 'throws (fail loud) when no key is available' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { $null }
                { Resolve-ImperionMyItProcessApiKey } | Should -Throw '*myITprocess API key unavailable*'
            }
        }
    }
}
