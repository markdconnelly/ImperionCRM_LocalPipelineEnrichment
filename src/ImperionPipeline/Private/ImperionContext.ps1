# Module-scoped runtime context. Initialize-ImperionContext (public) populates these; the
# private accessors below are used by every Invoke-* cmdlet so config/secret loading and
# token/DB plumbing live in one place.

function Get-ImperionConfig {
    if (-not $script:ImperionConfig) {
        throw 'Imperion context not initialized. Call Initialize-ImperionContext first.'
    }
    $script:ImperionConfig
}

function Get-ImperionSecretNames {
    if (-not $script:ImperionSecretNames) {
        throw 'Imperion context not initialized. Call Initialize-ImperionContext first.'
    }
    $script:ImperionSecretNames
}

function Get-ImperionSecretValue {
    param([Parameter(Mandatory)][string] $Name)
    $cfg = Get-ImperionConfig
    Get-Secret -Name $Name -AsPlainText -Vault $cfg.SecretVault
}

function Get-ImperionAppCredentialArg {
    # The enterprise-app credential splat for Get-ImperionAccessToken (frontend ADR-0103):
    # the SECRET when ClientSecretName is configured (read as a SecureString — never
    # plaintext, never logged), else the CERTIFICATE (the preferred default). Centralizing
    # this means every token wrapper supports cert OR secret with no per-call branching.
    $cfg = Get-ImperionConfig
    # $cfg is a Hashtable (Import-PowerShellDataFile) — probe the key the IDictionary way
    # (.Contains), NOT $cfg.PSObject.Properties[...] which never surfaces hashtable KEYS and so
    # silently always fell through to the certificate, even when a secret was configured.
    if (($cfg -is [System.Collections.IDictionary]) -and $cfg.Contains('ClientSecretName') -and $cfg.ClientSecretName) {
        return @{ ClientSecret = (Get-Secret -Name $cfg.ClientSecretName -Vault $cfg.SecretVault) }
    }
    return @{ CertThumbprint = $cfg.CertThumbprint }
}

function Get-ImperionTenantAppToken {
    # The shared per-tenant app-token seam (issues #250 m365 / #258 azure, epic #255, ADR-0028).
    # Every per-tenant Graph / ARM collector mints its token here, so per-client-app credential
    # resolution lives in ONE place for all providers:
    #   - no tenant / the partner (home) tenant -> the shared home enterprise-app credential
    #     (cert or secret). The home tenant carries no client-scope `connection` row by design,
    #     so this path stays DB-free (and avoids recursion: New-ImperionDbConnection itself mints
    #     a token via Get-ImperionAccessToken, not through here).
    #   - a managed CLIENT tenant -> authenticate as THAT client's OWN onboarding app, resolved
    #     from the GUI-mapped `connection` registry (account_tenant -> account_id ->
    #     Resolve-ImperionTenantCredential -Provider). The home app is NOT a fallback for a client
    #     tenant (it is not consented there and holds no client read grants); an unmapped or
    #     unconsented tenant FAILS CLOSED and is never touched (CLAUDE.md §3). The estate sweeps
    #     (Invoke-ImperionCloudResourceSync, the m365 collectors) isolate per tenant, so a throw
    #     becomes skip + Warn — one bad tenant never blocks the rest.
    # -Connection lets a caller that already holds a connection avoid reopening one.
    param(
        [Parameter(Mandatory)][string] $Resource,
        [string] $TenantId,
        [Parameter(Mandatory)][string] $Provider,
        $Connection
    )
    $cfg = Get-ImperionConfig

    if (-not $TenantId -or $TenantId -eq $cfg.PartnerTenantId) {
        $homeTenant = if ($TenantId) { $TenantId } else { $cfg.PartnerTenantId }
        $cred = Get-ImperionAppCredentialArg
        return Get-ImperionAccessToken -Resource $Resource -TenantId $homeTenant -ClientId $cfg.ClientId @cred
    }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }
    try {
        $mapping = Invoke-ImperionDbQuery -Connection $Connection `
            -Sql 'SELECT account_id FROM account_tenant WHERE tenant_id = @t::uuid LIMIT 1' `
            -Parameters @{ t = $TenantId } | Select-Object -First 1
        $accountId = if ($mapping) { $mapping.account_id } else { $null }
        if (-not $accountId) {
            throw "Tenant '$TenantId' is not mapped to an account (account_tenant) — fail closed; no $Provider token minted (CLAUDE.md §3)."
        }

        # Fail closed: the resolver throws if the client has no active, consented credential for
        # this provider. The returned splat already carries ClientId + TenantId + cert/secret, so
        # it is splatted straight into the token primitive.
        $cred = Resolve-ImperionTenantCredential -Connection $Connection -AccountId "$accountId" `
            -Provider $Provider -TenantId $TenantId -FailClosed
        return Get-ImperionAccessToken -Resource $Resource @cred
    }
    finally {
        if ($ownConnection) { $Connection.Dispose() }
    }
}

function Get-ImperionGraphToken {
    # m365 wrapper over the shared per-tenant seam (#250). Client tenants resolve their own
    # onboarding-app credential (provider 'm365'); partner/home keeps the shared cred.
    param([string] $TenantId, $Connection)
    Get-ImperionTenantAppToken -Resource 'https://graph.microsoft.com/.default' -TenantId $TenantId -Provider 'm365' -Connection $Connection
}

function Get-ImperionArmToken {
    # Azure ARM wrapper over the shared per-tenant seam (#258). Client tenants resolve their own
    # app credential (provider 'azure'); partner/home keeps the shared cred. This re-points the
    # per-client cloud-resource sweep (Get-ImperionCloudResource -> Invoke-ImperionCloudResourceSync)
    # at the client's own credential with zero collector edits.
    param([string] $TenantId, $Connection)
    Get-ImperionTenantAppToken -Resource 'https://management.azure.com/.default' -TenantId $TenantId -Provider 'azure' -Connection $Connection
}

function Get-ImperionKeyVaultToken {
    param([string] $TenantId)
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $cred = Get-ImperionAppCredentialArg
    Get-ImperionAccessToken -Resource 'https://vault.azure.net/.default' -TenantId $TenantId -ClientId $cfg.ClientId @cred
}

function Get-ImperionStorageToken {
    param([string] $TenantId)
    # Azure Storage data-plane token (the agreed Storage WRITE grant, CLAUDE.md §2) — used by the
    # receipt 90-day lifecycle to delete a verified-in-Autotask blob (ADR-0015).
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $cred = Get-ImperionAppCredentialArg
    Get-ImperionAccessToken -Resource 'https://storage.azure.com/.default' -TenantId $TenantId -ClientId $cfg.ClientId @cred
}

function New-ImperionDbConnection {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Opens a transient DB connection object; it changes no persistent system state, so ShouldProcess is not warranted.')]
    [CmdletBinding()]
    param()
    # Mint a short-lived Postgres token (ADR-0003) and open a connection from config.
    $cfg = Get-ImperionConfig
    $cred = Get-ImperionAppCredentialArg
    $token = Get-ImperionAccessToken -Resource 'https://ossrdbms-aad.database.windows.net/.default' -TenantId $cfg.PartnerTenantId -ClientId $cfg.ClientId @cred
    Open-ImperionDbConnection -DbHost $cfg.Db.Host -Database $cfg.Db.Database -Username $cfg.Db.Username -AccessToken $token -Port $cfg.Db.Port
}
