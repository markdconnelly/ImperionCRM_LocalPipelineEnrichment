#Requires -Modules Pester
# Issue #291 — on-prem IT Glue / KQM / Telivy resolve their company credential from the
# standardized credential-registry Key Vault name (conn-company-<provider>), the same secret the
# cloud reads, and skip the SecretStore mirror.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Vendor catalog — standardized conn-company-* (#291)' {
    It 'points itglue/telivy/kqm at the standardized Key Vault names, KV-only (no SecretStore key)' {
        InModuleScope ImperionPipeline {
            $cat = Get-ImperionVendorSecretCatalog
            $cat['itglue'].VaultDefault | Should -Be 'conn-company-itglue'
            $cat['telivy'].VaultDefault | Should -Be 'conn-company-televy'
            $cat['kqm'].VaultDefault    | Should -Be 'conn-company-quotemanager'
            # KV-only: no SecretStore mirror key on these three
            $cat['itglue'].Keys | Should -Not -Contain 'SecretStoreKey'
            $cat['telivy'].Keys | Should -Not -Contain 'SecretStoreKey'
            $cat['kqm'].Keys    | Should -Not -Contain 'SecretStoreKey'
        }
    }
}

Describe 'Company credential resolvers read Key Vault, skip the SecretStore mirror (#291)' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:ImperionSecretStoreVault = 'ImperionStore'  # simulate an unlocked vault
            Mock Get-ImperionSecretNames { @{} }                # context shim (no mirror titles)
            Mock Get-ImperionSecretValue { throw "tier-2 SecretStore must not be consulted (Name=$Name)" }
        }
    }

    It 'IT Glue reads conn-company-itglue and does not touch the SecretStore' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { "KV::$Name" }
            Resolve-ImperionITGlueApiKey | Should -Be 'KV::conn-company-itglue'
            Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'conn-company-itglue' }
            Should -Not -Invoke Get-ImperionSecretValue
        }
    }

    It 'Telivy reads conn-company-televy' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { "KV::$Name" }
            Resolve-ImperionTelivyApiKey | Should -Be 'KV::conn-company-televy'
            Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'conn-company-televy' }
        }
    }

    It 'KQM reads conn-company-quotemanager and stays caller-gated (null, no throw) when absent' {
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
