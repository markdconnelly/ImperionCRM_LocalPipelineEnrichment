#Requires -Modules Pester
# Hermetic tests for Connect-ImperionSecretStore. Unlock-SecretStore (SecretStore module, not
# installed here) is stubbed then mocked; Unprotect-CmsMessage is mocked so no real cert is needed.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        if (-not (Get-Command Unlock-SecretStore -ErrorAction SilentlyContinue)) {
            function script:Unlock-SecretStore { param($Password) }
        }
    }
}

Describe 'Connect-ImperionSecretStore' {
    It 'CMS-decrypts the vault password and unlocks the SecretStore' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $true }
            Mock Unprotect-CmsMessage { 'vault-password' }
            Mock Unlock-SecretStore { }
            Mock Write-ImperionLog { }

            Connect-ImperionSecretStore -CmsPasswordPath 'C:\ProgramData\Imperion\vault.cms' -VaultName 'ImperionStore'

            Should -Invoke Unprotect-CmsMessage -Times 1 -ParameterFilter { $Path -eq 'C:\ProgramData\Imperion\vault.cms' }
            Should -Invoke Unlock-SecretStore -Times 1
            $script:ImperionSecretStoreVault | Should -Be 'ImperionStore'
        }
    }

    It 'throws an actionable error when the CMS password file is missing' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $false }
            { Connect-ImperionSecretStore -CmsPasswordPath 'C:\nope\vault.cms' } | Should -Throw '*not found*'
        }
    }
}
