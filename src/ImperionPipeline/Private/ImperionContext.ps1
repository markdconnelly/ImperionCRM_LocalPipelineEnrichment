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

function Get-ImperionGraphToken {
    param([string] $TenantId)
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    Get-ImperionAccessToken -Resource 'https://graph.microsoft.com/.default' -TenantId $TenantId -ClientId $cfg.ClientId -CertThumbprint $cfg.CertThumbprint
}

function Get-ImperionArmToken {
    param([string] $TenantId)
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    Get-ImperionAccessToken -Resource 'https://management.azure.com/.default' -TenantId $TenantId -ClientId $cfg.ClientId -CertThumbprint $cfg.CertThumbprint
}

function Get-ImperionKeyVaultToken {
    param([string] $TenantId)
    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    Get-ImperionAccessToken -Resource 'https://vault.azure.net/.default' -TenantId $TenantId -ClientId $cfg.ClientId -CertThumbprint $cfg.CertThumbprint
}

function New-ImperionDbConnection {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Opens a transient DB connection object; it changes no persistent system state, so ShouldProcess is not warranted.')]
    [CmdletBinding()]
    param()
    # Mint a short-lived Postgres token (ADR-0003) and open a connection from config.
    $cfg = Get-ImperionConfig
    $token = Get-ImperionAccessToken -Resource 'https://ossrdbms-aad.database.windows.net/.default' -TenantId $cfg.PartnerTenantId -ClientId $cfg.ClientId -CertThumbprint $cfg.CertThumbprint
    Open-ImperionDbConnection -DbHost $cfg.Db.Host -Database $cfg.Db.Database -Username $cfg.Db.Username -AccessToken $token -Port $cfg.Db.Port
}
