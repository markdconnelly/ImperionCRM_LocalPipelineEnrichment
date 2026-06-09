@{
    # Certificate-backed Entra app (ADR-0002). Copy to pipeline.config.psd1 and fill in.
    CertThumbprint  = 'REPLACE_WITH_CERT_THUMBPRINT'
    ClientId        = 'REPLACE_WITH_ENTRA_APP_CLIENT_ID'
    PartnerTenantId = 'REPLACE_WITH_PARTNER_CSP_TENANT_ID'

    # Local SecretStore unlock (ADR-0002).
    CmsPasswordPath = 'C:\ProgramData\Imperion\vault.cms'
    SecretVault     = 'ImperionStore'

    LogDirectory    = 'C:\ProgramData\Imperion\logs'
    NpgsqlDllPath   = 'C:\ProgramData\Imperion\lib\Npgsql.dll'

    # Shared Azure PostgreSQL — short-lived token auth, no stored password (ADR-0003).
    Db = @{
        Host     = 'imperioncrm-pg-prd.postgres.database.azure.com'
        Database = 'imperioncrm'
        Username = 'imperion-localpipeline'   # the pgaadauth role mapped to the cert SP (migration 0044)
        Port     = 5432
    }

    ITGlue = @{
        BaseUri = 'https://api.itglue.com'   # use your region's base if different
    }

    # Azure Key Vault holding COMPANY credentials read by the cert SP (Key Vault Secrets User).
    # e.g. the Dark Web ID API key 'conn-company-darkwebid' (ADR-0040). Leave unset if no
    # source reads from Key Vault on this node.
    KeyVault = @{
        VaultUri = 'https://REPLACE_WITH_VAULT_NAME.vault.azure.net'
    }
}
