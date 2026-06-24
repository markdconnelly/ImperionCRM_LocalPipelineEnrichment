function Get-ImperionVendorSecretCatalog {
    <#
    .SYNOPSIS
        The per-vendor secret-resolution catalog: the only thing that differs between the
        company/MSP-wide vendor credentials that share the resolution shape.
    .DESCRIPTION
        Issue #319 (epic #318, supersedes the #228/ADR-0009 three-tier shape): company vendor
        credentials are resolved with the DATABASE `connection` registry as the authoritative
        link, so the backend, the cloud Pipeline, and this repo all read the SAME Key Vault
        secret. The local SecretStore is NO LONGER a credential source — its only remaining job
        is custody of the app credential that mints the Key Vault token (Get-ImperionAppCredentialArg).

        Two entry shapes; Resolve-ImperionVendorSecret owns the resolution once:

          REGISTRY-BACKED (a connection_provider enum value exists — the GUI writes the row):
            Provider      the connection_provider enum VALUE (DB-authoritative selector). Note
                          'televy' (not LP-internal 'telivy') and 'quotemanager' (KQM).
            Field         the JSON field to extract from the conn-company-<provider> blob.
            ErrorMessage  thrown verbatim when unresolved; $null = return $null (KQM is
                          caller-gated upstream).

          KV-BY-NAME (no connection registry row exists — LP-only vendors not in the FE
          registry: CDW, EasyDMARC, Datto RMM/BCDR, Amazon Business; plus Meta, whose LP read
          token differs from the FE send token — see #318):
            VaultSecret   the Key Vault secret title read directly via the cert SP.
            BlobField     OPTIONAL — extract this field when the secret is a JSON blob; absent =
                          bare-string secret.
            ErrorMessage  thrown verbatim when unresolved; $null = return $null.

        No secret VALUES live here — only the stable provider names / vault titles / field names.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()

    return @{
        # --- Registry-backed: DB connection row -> keyvault_secret_ref -> blob field ----------
        itglue = @{
            Provider     = 'itglue'
            Field        = 'apiKey'
            ErrorMessage = 'IT Glue API key unavailable: connect IT Glue in Settings -> Credentials (company) so the connection registry row + Key Vault secret exist (epic #318).'
        }
        # KQM's registry provider is 'quotemanager'; it stays caller-gated (ErrorMessage $null).
        kqm = @{
            Provider     = 'quotemanager'
            Field        = 'apiKey'
            ErrorMessage = $null
        }
        telivy = @{
            Provider     = 'televy'
            Field        = 'apiKey'
            ErrorMessage = 'Telivy API key unavailable: connect Televy in Settings -> Credentials (company) so the connection registry row + Key Vault secret exist (epic #318).'
        }
        myitprocess = @{
            Provider     = 'myitprocess'
            Field        = 'apiKey'
            ErrorMessage = 'myITprocess API key unavailable: connect My IT Process in Settings -> Credentials (company) so the connection registry row + Key Vault secret exist (epic #318).'
        }
        # Pax8 (epic #1042) — one connection row (provider 'pax8'), TWO blob fields; the OAuth2
        # client-credentials pair. Resolve-ImperionPax8Credential returns them together.
        pax8clientid = @{
            Provider     = 'pax8'
            Field        = 'clientId'
            ErrorMessage = 'Pax8 client id unavailable: connect Pax8 in Settings -> Credentials (company) so the connection registry row + Key Vault secret exist (issue #279, epic #1042).'
        }
        pax8secret = @{
            Provider     = 'pax8'
            Field        = 'clientSecret'
            ErrorMessage = 'Pax8 client secret unavailable: connect Pax8 in Settings -> Credentials (company) so the connection registry row + Key Vault secret exist (issue #279, epic #1042).'
        }

        # --- KV-by-name: LP-only vendors with no FE connection registry row ------------------
        cdw = @{
            VaultSecret  = 'CDW-API-Key'
            ErrorMessage = 'CDW API key unavailable: provision the Key Vault secret CDW-API-Key (issue #198).'
        }
        easydmarc = @{
            VaultSecret  = 'EasyDMARC-API-Key'
            ErrorMessage = 'EasyDMARC API key unavailable: provision the Key Vault secret EasyDMARC-API-Key (issue #122).'
        }
        dattobcdr = @{
            VaultSecret  = 'Datto-BCDR-API-Key'
            ErrorMessage = 'Datto BCDR API key unavailable: provision the Key Vault secret Datto-BCDR-API-Key (issue #195, ADR-0018).'
        }
        dattormm = @{
            VaultSecret  = 'Datto-RMM-API-Key'
            ErrorMessage = 'Datto RMM API key unavailable: provision the Key Vault secret Datto-RMM-API-Key (issue #195, ADR-0018).'
        }
        amazonbusiness = @{
            VaultSecret  = 'AmazonBusiness-Token'
            ErrorMessage = 'Amazon Business access token unavailable: provision the Key Vault secret AmazonBusiness-Token (issue #198).'
        }
        # Meta: the LP ingestion read token is the Business Manager SYSTEM-USER token
        # (Meta-SystemUser-Token), distinct from the FE conn-company-meta page-send token.
        # Kept KV-by-name until that token-type reconciliation lands (#318).
        meta = @{
            VaultSecret  = 'Meta-SystemUser-Token'
            ErrorMessage = 'Meta system-user token unavailable: provision the Key Vault secret Meta-SystemUser-Token (ADR-0013).'
        }
    }
}
