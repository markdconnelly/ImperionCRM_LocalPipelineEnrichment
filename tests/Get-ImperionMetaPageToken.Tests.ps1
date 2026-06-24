#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaPageToken + Resolve-ImperionMetaToken (issue #126).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaPageToken' {
    It 'fetches the page access token with the system-user token' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { , @([pscustomobject]@{ id = '123'; access_token = 'page-token' }) }
            $token = Get-ImperionMetaPageToken -PageId '123' -Token 'sys-token'
            $token | Should -Be 'page-token'
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Token -eq 'sys-token' -and $Uri -eq '123?fields=access_token'
            }
        }
    }

    It 'throws loudly when no page token comes back' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { , @([pscustomobject]@{ id = '123' }) }
            { Get-ImperionMetaPageToken -PageId '123' -Token 't' } | Should -Throw '*page access token*'
        }
    }

    It '-Discover lists pages with id, name, and token from /me/accounts' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{ id = '1'; name = 'Imperion'; access_token = 'pt1' })
            }
            $pages = @(Get-ImperionMetaPageToken -Discover -Token 't')
            $pages[0].page_id | Should -Be '1'
            $pages[0].page_name | Should -Be 'Imperion'
            $pages[0].page_token | Should -Be 'pt1'
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Uri -eq 'me/accounts?fields=id,name,access_token'
            }
        }
    }
}

Describe 'Resolve-ImperionMetaToken' {
    It 'an explicit token wins without touching the SecretStore' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretNames { throw 'must not be called' }
            Resolve-ImperionMetaToken -Token 'explicit' | Should -Be 'explicit'
        }
    }

    It 'reads the Meta-SystemUser-Token Key Vault secret directly, never the SecretStore (epic #318)' {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'TestVault'   # unlocked, but must not be read
            Mock Get-ImperionSecretValue { throw 'SecretStore must not be read for the Meta token' }
            Mock Get-ImperionKeyVaultSecret { 'kv-token' }
            try {
                Resolve-ImperionMetaToken | Should -Be 'kv-token'
                Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'Meta-SystemUser-Token' }
                Should -Not -Invoke Get-ImperionSecretValue
            }
            finally { $script:ImperionSecretStoreVault = $null }
        }
    }

    It 'throws loudly when the Key Vault secret is absent' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { $null }
            { Resolve-ImperionMetaToken } | Should -Throw '*Meta system-user token unavailable*'
        }
    }
}
