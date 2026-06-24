#Requires -Modules Pester
# Issue #291, now via the DB-authoritative registry (epic #318): on-prem IT Glue / KQM / Telivy
# resolve their company credential from the standardized credential-registry Key Vault secret
# (conn-company-<provider>) — the SAME secret the cloud reads — by following the `connection`
# row, and never consult the SecretStore.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Vendor catalog — registry-backed, standardized providers (#291/#318)' {
    It 'points itglue/telivy/kqm at the connection_provider enum value, registry-backed (no VaultDefault, no SecretStoreKey)' {
        InModuleScope ImperionPipeline {
            $cat = Get-ImperionVendorSecretCatalog
            $cat['itglue'].Provider | Should -Be 'itglue'
            $cat['telivy'].Provider | Should -Be 'televy'
            $cat['kqm'].Provider    | Should -Be 'quotemanager'
            foreach ($v in 'itglue', 'telivy', 'kqm') {
                $cat[$v].Field      | Should -Be 'apiKey'
                $cat[$v].Keys       | Should -Not -Contain 'SecretStoreKey'
                $cat[$v].Keys       | Should -Not -Contain 'VaultDefault'
            }
        }
    }
}

Describe 'Company credential resolvers follow the registry to Key Vault, skip the SecretStore (#291/#318)' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'ImperionStore'  # simulate an unlocked vault
            Mock Get-ImperionSecretValue { throw "SecretStore must not be consulted (Name=$Name)" }
            # Own-connection path: a disposable stand-in (built inside the mock so it resolves at
            # invocation time) + the registry row per provider.
            Mock New-ImperionDbConnection {
                $c = [pscustomobject]@{}
                $c | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
                $c
            }
            Mock Invoke-ImperionDbQuery {
                $name = "conn-company-$($Parameters['provider'])"
                [pscustomobject]@{ keyvault_secret_ref = $name }
            }
        }
    }

    It 'IT Glue follows the row to conn-company-itglue and does not touch the SecretStore' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { "KV::$Name" }
            Resolve-ImperionITGlueApiKey | Should -Be 'KV::conn-company-itglue'
            Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'conn-company-itglue' }
            Should -Not -Invoke Get-ImperionSecretValue
        }
    }

    It 'Telivy follows the row to conn-company-televy (DB provider enum value)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { "KV::$Name" }
            Resolve-ImperionTelivyApiKey | Should -Be 'KV::conn-company-televy'
            Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'conn-company-televy' }
        }
    }

    It 'KQM follows the row to conn-company-quotemanager, caller-gated (null, no throw) when absent' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { $null }
            $key = $null
            { $key = Resolve-ImperionKqmApiKey } | Should -Not -Throw
            $key | Should -BeNullOrEmpty
            Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'conn-company-quotemanager' }
        }
    }

    It 'IT Glue throws (fail loudly) when the Key Vault secret is absent' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { $null }
            { Resolve-ImperionITGlueApiKey } | Should -Throw
        }
    }
}

Describe 'Collectors route through the standardized resolver (#291)' {
    It 'Get-ImperionITGlueOrganization resolves via Resolve-ImperionITGlueApiKey' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1'; ITGlue = @{ BaseUri = 'https://itg' } } }
            Mock Resolve-ImperionITGlueApiKey { 'K' }
            Mock Invoke-ImperionITGlueRequest { , @() }
            Get-ImperionITGlueOrganization | Out-Null
            Should -Invoke Resolve-ImperionITGlueApiKey -Times 1
        }
    }

    It 'Get-ImperionTelivyReport resolves via Resolve-ImperionTelivyApiKey' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Resolve-ImperionTelivyApiKey { 'K' }
            Mock Invoke-ImperionTelivyRequest { , @() }
            Get-ImperionTelivyReport -BaseUri 'https://telivy' | Out-Null
            Should -Invoke Resolve-ImperionTelivyApiKey -Times 1
        }
    }
}
