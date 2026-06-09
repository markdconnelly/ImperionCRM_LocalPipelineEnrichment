#Requires -Modules Pester
# Hermetic test for Get-ImperionKeyVaultSecret: token + KV REST mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKeyVaultSecret' {
    It 'reads a secret from the configured vault and returns its value' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ KeyVault = @{ VaultUri = 'https://kv1.vault.azure.net' } } }
            Mock Get-ImperionKeyVaultToken { 'kv-token' }
            $captured = $null
            Mock Invoke-ImperionRestWithRetry {
                $script:captured = @{ Uri = $Uri; Auth = $Headers.Authorization }
                [pscustomobject]@{ Body = [pscustomobject]@{ value = 'sekret!' } }
            }

            $val = Get-ImperionKeyVaultSecret -Name 'conn-company-darkwebid'

            $val | Should -Be 'sekret!'
            $script:captured.Uri  | Should -Be 'https://kv1.vault.azure.net/secrets/conn-company-darkwebid?api-version=7.4'
            $script:captured.Auth | Should -Be 'Bearer kv-token'
        }
    }

    It 'honours an explicit -VaultUri over config' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ KeyVault = @{ VaultUri = 'https://kv1.vault.azure.net' } } }
            Mock Get-ImperionKeyVaultToken { 't' }
            $captured = $null
            Mock Invoke-ImperionRestWithRetry { $script:captured = @{ Uri = $Uri }; [pscustomobject]@{ Body = [pscustomobject]@{ value = 'x' } } }

            Get-ImperionKeyVaultSecret -Name 's' -VaultUri 'https://other.vault.azure.net/' | Out-Null
            $script:captured.Uri | Should -Match '^https://other\.vault\.azure\.net/secrets/s\?'
        }
    }

    It 'throws when no vault URI is available' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ } }   # no KeyVault block
            Mock Get-ImperionKeyVaultToken { 't' }
            Mock Invoke-ImperionRestWithRetry { throw 'should not be called' }
            { Get-ImperionKeyVaultSecret -Name 's' } | Should -Throw '*Key Vault URI*'
        }
    }

    It 'throws when the secret has no value' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ KeyVault = @{ VaultUri = 'https://kv1.vault.azure.net' } } }
            Mock Get-ImperionKeyVaultToken { 't' }
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ } } }
            { Get-ImperionKeyVaultSecret -Name 'missing' } | Should -Throw '*no value*'
        }
    }
}
