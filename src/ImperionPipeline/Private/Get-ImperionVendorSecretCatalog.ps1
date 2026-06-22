function Get-ImperionVendorSecretCatalog {
    <#
    .SYNOPSIS
        The per-vendor secret-resolution catalog: the only thing that differs between the
        company/MSP-wide vendor credentials that share the three-tier resolution shape.
    .DESCRIPTION
        Issue #228 (ADR-0009): the vendor key/token resolvers (CDW, EasyDMARC, myITprocess,
        Datto BCDR/RMM, KQM, Meta, Amazon Business) were line-for-line duplicates of one shape —
        explicit value, else the SecretStore mirror, else the Key Vault original, else throw.
        This catalog holds the per-vendor differences; Resolve-ImperionVendorSecret owns the
        shape once. Each vendor's named resolver (Resolve-Imperion<Vendor>ApiKey / *Token) is a
        thin adapter over that pair, so call sites and error contracts are unchanged.

        Per entry:
          SecretStoreKey        secret-names config key naming the SecretStore mirror title
          VaultSecretConfigKey  secret-names config key that, when present, overrides the Key
                                Vault secret title
          VaultDefault          Key Vault secret title used when VaultSecretConfigKey is absent
          BlobField             OPTIONAL — when set, the Key Vault value is a JSON credential
                                blob (conn-company-<provider>, issue #299) and this names the
                                field to extract; absent = the secret is a bare string
          ErrorMessage          thrown verbatim when the value is unresolved; $null = return
                                $null without throwing (KQM is caller-gated upstream)

        No secret VALUES live here — only the stable names (mirrors config/secret-names).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()

    return @{
        cdw = @{
            SecretStoreKey       = 'CdwApiKey'
            VaultSecretConfigKey = 'CdwApiKeyVaultSecret'
            VaultDefault         = 'CDW-API-Key'
            ErrorMessage         = 'CDW API key unavailable: pass -ApiKey, provision the SecretStore secret named by CdwApiKey, or the Key Vault secret named by CdwApiKeyVaultSecret (issue #198).'
        }
        easydmarc = @{
            SecretStoreKey       = 'EasyDmarcApiKey'
            VaultSecretConfigKey = 'EasyDmarcApiKeyVaultSecret'
            VaultDefault         = 'EasyDMARC-API-Key'
            ErrorMessage         = 'EasyDMARC API key unavailable: pass -ApiKey, provision the SecretStore secret named by EasyDmarcApiKey, or the Key Vault secret named by EasyDmarcApiKeyVaultSecret (issue #122).'
        }
        # Rerouted to the standardized credential-registry name (conn-company-myitprocess),
        # the same KV-only JSON-blob shape as itglue/telivy/kqm (#291/#292 → #299). The
        # legacy myITprocess-API-Key + SecretStore mirror are retired.
        myitprocess = @{
            VaultDefault = 'conn-company-myitprocess'
            BlobField    = 'apiKey'
            ErrorMessage = 'myITprocess API key unavailable: provision the Key Vault secret conn-company-myitprocess via the credential registry (issue #292).'
        }
        dattobcdr = @{
            SecretStoreKey       = 'DattoBcdrApiKey'
            VaultSecretConfigKey = 'DattoBcdrApiKeyVaultSecret'
            VaultDefault         = 'Datto-BCDR-API-Key'
            ErrorMessage         = 'Datto BCDR API key unavailable: pass -ApiKey, provision the SecretStore secret named by DattoBcdrApiKey, or the Key Vault secret named by DattoBcdrApiKeyVaultSecret (issue #195, ADR-0018).'
        }
        dattormm = @{
            SecretStoreKey       = 'DattoRmmApiKey'
            VaultSecretConfigKey = 'DattoRmmApiKeyVaultSecret'
            VaultDefault         = 'Datto-RMM-API-Key'
            ErrorMessage         = 'Datto RMM API key unavailable: pass -ApiKey, provision the SecretStore secret named by DattoRmmApiKey, or the Key Vault secret named by DattoRmmApiKeyVaultSecret (issue #195, ADR-0018).'
        }
        # Standardized credential-registry resolution (conn-company-<provider>): the same Key
        # Vault secrets the cloud reads (issue #291; Mark 2026-06-21 "leverage KV like the cloud").
        # These entries omit SecretStoreKey/VaultSecretConfigKey on purpose, so the resolver
        # skips the SecretStore mirror AND any stale per-host override and reads the Key Vault
        # secret below via the cert SP. KQM's registry provider is 'quotemanager'; it stays
        # caller-gated (ErrorMessage $null = return $null, don't throw).
        # BlobField: the credential registry stores conn-company-<provider> as a JSON
        # credential blob (backend credentials.ts: setSecret(name, JSON.stringify(fields))),
        # NOT a bare string — the field named here is extracted from that blob (issue #299).
        # The FE company-providers form posts the API key under 'apiKey' for all four.
        kqm = @{
            VaultDefault = 'conn-company-quotemanager'
            BlobField    = 'apiKey'
            ErrorMessage = $null
        }
        itglue = @{
            VaultDefault = 'conn-company-itglue'
            BlobField    = 'apiKey'
            ErrorMessage = 'IT Glue API key unavailable: provision the Key Vault secret conn-company-itglue via the credential registry (issue #291).'
        }
        telivy = @{
            VaultDefault = 'conn-company-televy'
            BlobField    = 'apiKey'
            ErrorMessage = 'Telivy API key unavailable: provision the Key Vault secret conn-company-televy via the credential registry (issue #291).'
        }
        meta = @{
            SecretStoreKey       = 'MetaSystemUserToken'
            VaultSecretConfigKey = 'MetaTokenVaultSecret'
            VaultDefault         = 'Meta-SystemUser-Token'
            ErrorMessage         = 'Meta system-user token unavailable: pass -Token, provision the SecretStore secret named by MetaSystemUserToken, or the Key Vault secret named by MetaTokenVaultSecret (ADR-0013).'
        }
        amazonbusiness = @{
            SecretStoreKey       = 'AmazonBusinessToken'
            VaultSecretConfigKey = 'AmazonBusinessTokenVaultSecret'
            VaultDefault         = 'AmazonBusiness-Token'
            ErrorMessage         = 'Amazon Business access token unavailable: pass -Token, provision the SecretStore secret named by AmazonBusinessToken, or the Key Vault secret named by AmazonBusinessTokenVaultSecret (issue #198).'
        }
    }
}
