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

function Get-ImperionNodeCredentialArg {
    # This LP node's OWN Entra app credential splat for Get-ImperionAccessToken (frontend ADR-0103):
    # the SECRET when ClientSecretName is configured (read as a SecureString — never plaintext,
    # never logged), else the CERTIFICATE (the preferred default). Used ONLY to mint the node's
    # infra/bootstrap tokens (Postgres / Key Vault / Storage) — never a per-tenant data read, which
    # resolves its own app from the registry (Get-ImperionRegisteredTenantToken, ADR-0030).
    # Centralizing this means every bootstrap token supports cert OR secret with no per-call branching.
    $cfg = Get-ImperionConfig
    # $cfg is a Hashtable (Import-PowerShellDataFile) — probe the key the IDictionary way
    # (.Contains), NOT $cfg.PSObject.Properties[...] which never surfaces hashtable KEYS and so
    # silently always fell through to the certificate, even when a secret was configured.
    if (($cfg -is [System.Collections.IDictionary]) -and $cfg.Contains('ClientSecretName') -and $cfg.ClientSecretName) {
        return @{ ClientSecret = (Get-Secret -Name $cfg.ClientSecretName -Vault $cfg.SecretVault) }
    }
    return @{ CertThumbprint = $cfg.CertThumbprint }
}

function Get-ImperionRegisteredTenantToken {
    # The shared per-tenant data-read token seam (#250 m365 / #258 azure, epic #255/#324, ADR-0030).
    # Every per-tenant Graph / ARM collector mints its token here, so per-tenant credential
    # resolution lives in ONE place for all providers. There is NO partner/home special-case:
    # every tenant (Imperion included) resolves its app credential from the GUI-mapped `connection`
    # registry (account_tenant -> account_id -> Resolve-ImperionTenantCredential -Provider), cert OR
    # secret per `auth_method`. The home tenant is just the default `TenantId`, not a branch — it
    # carries its own `connection` row (the consented onboarding app), the same as any client.
    #   - An unmapped or unconsented tenant FAILS CLOSED and is never touched (CLAUDE.md §3). The
    #     estate sweeps (Invoke-ImperionCloudResourceSync, the m365 collectors) isolate per tenant,
    #     so a throw becomes skip + Warn — one bad tenant never blocks the rest.
    # The LP config SP (`$cfg.ClientId`) is reserved for INFRA/bootstrap tokens only (Postgres /
    # Key Vault / Storage — see Get-ImperionKeyVaultToken / -StorageToken / New-ImperionDbConnection)
    # and is never used for a data read here. No recursion: New-ImperionDbConnection mints its PG
    # token via Get-ImperionAccessToken directly, not through this seam.
    # -Connection lets a caller that already holds a connection avoid reopening one.
    param(
        [Parameter(Mandatory)][string] $Resource,
        [string] $TenantId,
        [Parameter(Mandatory)][string] $Provider,
        $Connection
    )
    if (-not $TenantId) { $TenantId = (Get-ImperionConfig).PartnerTenantId }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }
    try {
        $mapping = Invoke-ImperionDbQuery -Connection $Connection `
            -Sql 'SELECT account_id FROM account_tenant WHERE tenant_id = @t LIMIT 1' `
            -Parameters @{ t = $TenantId } | Select-Object -First 1
        $accountId = if ($mapping) { $mapping.account_id } else { $null }
        if (-not $accountId) {
            throw "Tenant '$TenantId' is not mapped to an account (account_tenant) — fail closed; no $Provider token minted (CLAUDE.md §3)."
        }

        # Fail closed: the resolver throws if the tenant has no active, consented credential for
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

# Back-compat alias for one release (ADR-0030): the old name read as "get a token" but is the
# registry-resolve + connect seam. Remove next release once no out-of-tree caller references it.
Set-Alias -Name Get-ImperionTenantAppToken -Value Get-ImperionRegisteredTenantToken

function Get-ImperionGraphToken {
    # m365 wrapper over the shared per-tenant seam (#250). EVERY tenant (Imperion included)
    # resolves its own onboarding-app credential from the registry (provider 'm365').
    param([string] $TenantId, $Connection)
    Get-ImperionRegisteredTenantToken -Resource 'https://graph.microsoft.com/.default' -TenantId $TenantId -Provider 'm365' -Connection $Connection
}

function Get-ImperionArmToken {
    # Azure ARM wrapper over the shared per-tenant seam (#258, ADR-0030). ARM reuses the SAME
    # per-tenant onboarding-app credential as Graph (provider 'm365') — one read-only app per
    # tenant covers Graph AND Azure ARM (the onboarding app holds Global Reader on the tenant
    # root management group). No separate 'azure' provider row, and no config-SP fallback: every
    # tenant (Imperion included) resolves from the registry. Re-points the per-tenant cloud-resource
    # sweep (Get-ImperionCloudResource -> Invoke-ImperionCloudResourceSync) with zero collector edits.
    param([string] $TenantId, $Connection)
    Get-ImperionRegisteredTenantToken -Resource 'https://management.azure.com/.default' -TenantId $TenantId -Provider 'm365' -Connection $Connection
}

function Get-ImperionKeyVaultToken {
    param([string] $TenantId)
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $cred = Get-ImperionNodeCredentialArg
    Get-ImperionAccessToken -Resource 'https://vault.azure.net/.default' -TenantId $TenantId -ClientId $cfg.ClientId @cred
}

function Get-ImperionStorageToken {
    param([string] $TenantId)
    # Azure Storage data-plane token (the agreed Storage WRITE grant, CLAUDE.md §2) — used by the
    # receipt 90-day lifecycle to delete a verified-in-Autotask blob (ADR-0015).
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $cred = Get-ImperionNodeCredentialArg
    Get-ImperionAccessToken -Resource 'https://storage.azure.com/.default' -TenantId $TenantId -ClientId $cfg.ClientId @cred
}

function New-ImperionDbConnection {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Opens a transient DB connection object; it changes no persistent system state, so ShouldProcess is not warranted.')]
    [CmdletBinding()]
    param()
    # Mint a short-lived Postgres token (ADR-0003) and open a connection from config.
    $cfg = Get-ImperionConfig
    $cred = Get-ImperionNodeCredentialArg
    $token = Get-ImperionAccessToken -Resource 'https://ossrdbms-aad.database.windows.net/.default' -TenantId $cfg.PartnerTenantId -ClientId $cfg.ClientId @cred
    Open-ImperionDbConnection -DbHost $cfg.Db.Host -Database $cfg.Db.Database -Username $cfg.Db.Username -AccessToken $token -Port $cfg.Db.Port
}
