#Requires -Modules Pester
# Hermetic unit tests for the deep vendor secret resolver (epic #318, supersedes #228) and the
# thin per-vendor adapters that delegate to it. Pins the resolution order (explicit ->
# DB-authoritative registry / KV-by-name -> throw), the EXACT thrown message per vendor (a
# non-negotiable contract — callers/scheduled tasks read it), the KQM outlier that returns $null,
# and that the local SecretStore is NEVER consulted for a vendor secret.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionVendorSecret' {

    BeforeEach {
        InModuleScope ImperionPipeline {
            # The SecretStore is no longer a credential source — assert it is never read.
            Mock Get-ImperionSecretValue { throw 'SecretStore must not be read for vendor secrets' }
        }
    }

    Context 'explicit value short-circuits everything' {
        It 'returns an explicit -Value without touching the DB or any vault' {
            InModuleScope ImperionPipeline {
                Mock Resolve-ImperionCompanyCredential { throw 'should not be called' }
                Mock Get-ImperionKeyVaultSecret { throw 'should not be called' }
                Resolve-ImperionVendorSecret -Vendor 'itglue' -Value 'explicit' | Should -Be 'explicit'
            }
        }
    }

    Context 'registry-backed (itglue) — DB-authoritative' {
        It 'delegates to Resolve-ImperionCompanyCredential with the provider + field' {
            InModuleScope ImperionPipeline {
                Mock Resolve-ImperionCompanyCredential {
                    $Provider | Should -Be 'itglue'
                    $Field    | Should -Be 'apiKey'
                    'itg-real'
                }
                Resolve-ImperionVendorSecret -Vendor 'itglue' | Should -Be 'itg-real'
            }
        }
        It 'throws the exact catalog message when the registry resolves nothing' {
            InModuleScope ImperionPipeline {
                Mock Resolve-ImperionCompanyCredential { $null }
                { Resolve-ImperionVendorSecret -Vendor 'itglue' } |
                    Should -Throw -ExpectedMessage 'IT Glue API key unavailable: connect IT Glue in Settings -> Credentials (company) so the connection registry row + Key Vault secret exist (epic #318).'
            }
        }
    }

    Context 'KV-by-name (cdw) — LP-only vendor, no registry row' {
        It 'reads the named Key Vault secret directly' {
            InModuleScope ImperionPipeline {
                Mock Resolve-ImperionCompanyCredential { throw 'cdw has no registry row — must not call the company resolver' }
                Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'CDW-API-Key') { 'kv' } else { throw "wrong name $Name" } }
                Resolve-ImperionVendorSecret -Vendor 'cdw' | Should -Be 'kv'
            }
        }
        It 'throws the exact catalog message when the Key Vault secret is absent' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionKeyVaultSecret { $null }
                { Resolve-ImperionVendorSecret -Vendor 'cdw' } |
                    Should -Throw -ExpectedMessage 'CDW API key unavailable: provision the Key Vault secret CDW-API-Key (issue #198).'
            }
        }
    }

    Context 'KQM outlier — returns $null, never throws' {
        It 'returns $null (no throw) when the registry resolves nothing' {
            InModuleScope ImperionPipeline {
                Mock Resolve-ImperionCompanyCredential { $null }
                { Resolve-ImperionVendorSecret -Vendor 'kqm' } | Should -Not -Throw
                Resolve-ImperionVendorSecret -Vendor 'kqm' | Should -BeNullOrEmpty
            }
        }
    }

    Context 'unknown vendor' {
        It 'throws a clear error for an unknown catalog key' {
            InModuleScope ImperionPipeline {
                { Resolve-ImperionVendorSecret -Vendor 'nope' } | Should -Throw -ExpectedMessage "Unknown vendor secret 'nope':*"
            }
        }
    }

    Context 'every catalog entry is well-formed' {
        It 'has ErrorMessage and exactly one resolution shape (Provider+Field XOR VaultSecret)' {
            InModuleScope ImperionPipeline {
                $catalog = Get-ImperionVendorSecretCatalog
                foreach ($vendor in $catalog.Keys) {
                    $spec = $catalog[$vendor]
                    $spec.Contains('ErrorMessage') | Should -BeTrue -Because "$vendor needs ErrorMessage (may be `$null)"
                    $isRegistry = $spec.Contains('Provider')
                    $isKvByName = $spec.Contains('VaultSecret')
                    ($isRegistry -xor $isKvByName) | Should -BeTrue -Because "$vendor must be registry-backed XOR KV-by-name"
                    if ($isRegistry) { $spec.Contains('Field') | Should -BeTrue -Because "$vendor (registry) needs Field" }
                }
            }
        }
    }
}

Describe 'per-vendor adapters delegate to the deep resolver' {

    BeforeEach {
        InModuleScope ImperionPipeline { Mock Get-ImperionSecretValue { throw 'SecretStore must not be read' } }
    }

    It 'Resolve-ImperionMetaToken resolves via the meta (KV-by-name) entry; -Token preserved' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { if ($Name -eq 'Meta-SystemUser-Token') { 'meta-kv' } else { throw "wrong name $Name" } }
            Resolve-ImperionMetaToken | Should -Be 'meta-kv'
            Resolve-ImperionMetaToken -Token 'explicit-tok' | Should -Be 'explicit-tok'
        }
    }

    It 'Resolve-ImperionMetaToken throws the exact Meta message when unresolved' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { $null }
            { Resolve-ImperionMetaToken } | Should -Throw -ExpectedMessage 'Meta system-user token unavailable: provision the Key Vault secret Meta-SystemUser-Token (ADR-0013).'
        }
    }

    It 'Resolve-ImperionITGlueApiKey delegates to the registry path' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionCompanyCredential { if ($Provider -eq 'itglue' -and $Field -eq 'apiKey') { 'itg' } else { throw 'wrong args' } }
            Resolve-ImperionITGlueApiKey | Should -Be 'itg'
        }
    }

    It 'Resolve-ImperionCdwApiKey delegates and returns an explicit -ApiKey' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { throw 'should not be called' }
            Resolve-ImperionCdwApiKey -ApiKey 'explicit' | Should -Be 'explicit'
        }
    }
}
