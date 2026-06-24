#Requires -Modules Pester
# Hermetic unit tests for the three private RMM/managed-estate key resolvers (issue #195, ADR-0018;
# epic #318): Resolve-ImperionDattoRmmApiKey / Resolve-ImperionDattoBcdrApiKey /
# Resolve-ImperionMyItProcessApiKey. Datto RMM/BCDR are LP-only vendors (no FE registry row) →
# KV-by-name; myITprocess is registry-backed → DB connection row -> Key Vault. The SecretStore is
# never consulted. No secret VALUES anywhere — only stable names.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'RMM/managed-estate key resolvers' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'vault'   # unlocked — but must never be read
            Mock Get-ImperionSecretValue { throw "SecretStore must not be read (Name=$Name)" }
        }
    }

    Context 'Resolve-ImperionDattoRmmApiKey (KV-by-name)' {
        It 'returns an explicit -ApiKey without touching any vault' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { throw 'should not be called' }
                Resolve-ImperionDattoRmmApiKey -ApiKey 'explicit' | Should -Be 'explicit'
            }
        }
        It 'reads the named Key Vault secret directly, never the SecretStore' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'Datto-RMM-API-Key') { 'kv-key' } else { throw "wrong name $Name" } }
                Resolve-ImperionDattoRmmApiKey | Should -Be 'kv-key'
                Should -Not -Invoke Get-ImperionSecretValue
            }
        }
        It 'throws (fail loud) when no key is available' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { $null }
                { Resolve-ImperionDattoRmmApiKey } | Should -Throw '*Datto RMM API key unavailable*'
            }
        }
    }

    Context 'Resolve-ImperionDattoBcdrApiKey (KV-by-name)' {
        It 'reads the named Key Vault secret directly' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'Datto-BCDR-API-Key') { 'kv-key' } else { throw "wrong name $Name" } }
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

    Context 'Resolve-ImperionMyItProcessApiKey (registry-backed, DB row -> Key Vault)' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                Mock New-ImperionDbConnection {
                    $c = [pscustomobject]@{}
                    $c | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
                    $c
                }
                Mock Invoke-ImperionDbQuery {
                    $Parameters['provider'] | Should -Be 'myitprocess'
                    [pscustomobject]@{ keyvault_secret_ref = 'conn-company-myitprocess' }
                }
            }
        }
        It 'follows the registry row and extracts apiKey from the conn-company-myitprocess blob' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'conn-company-myitprocess') { '{"apiKey":"kv-key"}' } else { throw "wrong name $Name" } }
                Resolve-ImperionMyItProcessApiKey | Should -Be 'kv-key'
                Should -Not -Invoke Get-ImperionSecretValue
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
