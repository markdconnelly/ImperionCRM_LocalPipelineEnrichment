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
        Host     = 'imperioncrm.postgres.database.azure.com'
        Database = 'imperion'
        Username = 'REPLACE_WITH_SP_POSTGRES_ROLE_NAME'   # the Entra principal name of the SP
        Port     = 5432
    }

    ITGlue = @{
        BaseUri = 'https://api.itglue.com'   # use your region's base if different
    }
}
