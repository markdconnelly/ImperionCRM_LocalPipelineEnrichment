#Requires -Modules Pester
# Hermetic unit tests for the private Resolve-ImperionMileIqAccessToken: per-employee token
# resolution and the dormant-per-employee no-op (a missing secret -> $null, never a throw).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionMileIqAccessToken' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretNames { @{ MileIqTokenPrefix = 'mileiq-token-'; MileIqTokenVaultPrefix = 'MileIQ-Token-' } }
        }
    }

    It 'returns an explicit -AccessToken without touching any vault' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretValue { throw 'should not be called' }
            Mock Get-ImperionKeyVaultSecret { throw 'should not be called' }
            Resolve-ImperionMileIqAccessToken -MileIqUserId 'mq-1' -AccessToken 'explicit' | Should -Be 'explicit'
        }
    }

    It 'reads the SecretStore mirror titled <prefix><userId> when the vault is unlocked' {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'vault'
            Mock Get-ImperionSecretValue { if ($Name -eq 'mileiq-token-mq-7') { 'mirror-tok' } else { throw 'wrong name' } }
            Mock Get-ImperionKeyVaultSecret { throw 'should not reach Key Vault' }
            Resolve-ImperionMileIqAccessToken -MileIqUserId 'mq-7' | Should -Be 'mirror-tok'
        }
    }

    It 'falls back to the Key Vault original titled <vaultPrefix><userId> when the mirror is absent' {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'vault'
            Mock Get-ImperionSecretValue { throw 'not found' }   # SecretStore miss
            Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'MileIQ-Token-mq-7') { 'kv-tok' } else { throw 'wrong name' } }
            Resolve-ImperionMileIqAccessToken -MileIqUserId 'mq-7' | Should -Be 'kv-tok'
        }
    }

    It 'returns $null (no throw) when neither store has the secret (dormant-per-employee)' {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'vault'
            Mock Get-ImperionSecretValue { throw 'not found' }
            Mock Get-ImperionKeyVaultSecret { throw 'not found' }
            { Resolve-ImperionMileIqAccessToken -MileIqUserId 'mq-x' } | Should -Not -Throw
            Resolve-ImperionMileIqAccessToken -MileIqUserId 'mq-x' | Should -BeNullOrEmpty
        }
    }

    It 'skips the SecretStore entirely when the vault is locked and tries Key Vault only' {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = $null
            Mock Get-ImperionSecretValue { throw 'vault locked - should not be called' }
            Mock Get-ImperionKeyVaultSecret { 'kv-only' }
            Resolve-ImperionMileIqAccessToken -MileIqUserId 'mq-1' | Should -Be 'kv-only'
            Should -Invoke Get-ImperionSecretValue -Times 0
        }
    }
}
