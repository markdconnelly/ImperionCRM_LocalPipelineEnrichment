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

function Get-ImperionGraphToken {
    # The per-tenant Graph-token seam (issue #250, epic #255, ADR-0028). Every m365 collector
    # mints its token here, so per-client-app credential resolution lives in ONE place:
    #   - no tenant / the partner (home) tenant -> the shared home enterprise-app credential
    #     (cert or secret). The home tenant carries no client-scope `connection` row by design,
    #     so this path stays DB-free (and avoids recursion: New-ImperionDbConnection itself mints
    #     a token via Get-ImperionAccessToken, not through here).
    #   - a managed CLIENT tenant -> authenticate as THAT client's OWN onboarding app, resolved
    #     from the GUI-mapped `connection` registry (account_tenant -> account_id ->
    #     Resolve-ImperionTenantCredential -Provider m365). The home app is NOT a fallback for a
    #     client tenant (it is not consented there and holds no client read grants); an unmapped
    #     or unconsented tenant FAILS CLOSED and is never touched (CLAUDE.md §3).
    # -Connection lets a caller that already holds a connection avoid reopening one.
    param(
        [string] $TenantId,
        $Connection
    )
    $cfg = Get-ImperionConfig

    if (-not $TenantId -or $TenantId -eq $cfg.PartnerTenantId) {
        $homeTenant = if ($TenantId) { $TenantId } else { $cfg.PartnerTenantId }
        $cred = Get-ImperionAppCredentialArg
        return Get-ImperionAccessToken -Resource 'https://graph.microsoft.com/.default' -TenantId $homeTenant -ClientId $cfg.ClientId @cred
    }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }
    try {
        $mapping = Invoke-ImperionDbQuery -Connection $Connection `
            -Sql 'SELECT account_id FROM account_tenant WHERE tenant_id = @t::uuid LIMIT 1' `
            -Parameters @{ t = $TenantId } | Select-Object -First 1
        $accountId = if ($mapping) { $mapping.account_id } else { $null }
        if (-not $accountId) {
            throw "Tenant '$TenantId' is not mapped to an account (account_tenant) — fail closed; no Graph token minted (CLAUDE.md §3)."
        }

        # Fail closed: the resolver throws if the client has no active, consented m365 credential.
        # The returned splat already carries ClientId + TenantId + cert/secret, so it is splatted
        # straight into the token primitive.
        $cred = Resolve-ImperionTenantCredential -Connection $Connection -AccountId "$accountId" `
            -Provider 'm365' -TenantId $TenantId -FailClosed
        return Get-ImperionAccessToken -Resource 'https://graph.microsoft.com/.default' @cred
    }
    finally {
        if ($ownConnection) { $Connection.Dispose() }
    }
}

function Get-ImperionArmToken {
    param([string] $TenantId)
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $cred = Get-ImperionAppCredentialArg
    Get-ImperionAccessToken -Resource 'https://management.azure.com/.default' -TenantId $TenantId -ClientId $cfg.ClientId @cred
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
