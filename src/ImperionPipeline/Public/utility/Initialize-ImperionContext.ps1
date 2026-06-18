function Initialize-ImperionContext {
    <#
    .SYNOPSIS
        Load configuration, set runtime paths, and unlock the SecretStore (call once before any Invoke-* cmdlet).
    .DESCRIPTION
        Replaces the old _bootstrap script now that this is an installed module. Reads
        pipeline config + secret-name map (from ProgramData by default, so machine config
        lives outside the module), sets the log and Npgsql paths consumed by the module, and
        unlocks the local SecretStore via the certificate (ADR-0002). Idempotent.
    .PARAMETER ConfigPath
        Path to pipeline.config.psd1. Default: $env:ProgramData\Imperion\pipeline.config.psd1
        (override with $env:IMPERION_CONFIG).
    .PARAMETER SecretNamesPath
        Path to secret-names.psd1. Default: alongside the config.
    .PARAMETER SkipSecretStore
        Initialize WITHOUT unlocking the local SecretStore. Interim mode for a host where
        the service identity (and therefore its per-user-profile vault) is not provisioned
        yet: cmdlets that resolve secrets from Key Vault (Dark Web ID, the Voyage embedding
        key fallback) still work; any cmdlet that needs a SecretStore-only secret fails
        loudly at its Get-Secret call. The unattended end-state does NOT use this switch.
    .EXAMPLE
        Import-Module ImperionPipeline; Initialize-ImperionContext
    .EXAMPLE
        # Interim (no service account yet): Key-Vault-backed secrets only.
        Initialize-ImperionContext -SkipSecretStore
    #>
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $SecretNamesPath,
        [switch] $SkipSecretStore
    )

    if (-not $ConfigPath) {
        $ConfigPath = if ($env:IMPERION_CONFIG) { $env:IMPERION_CONFIG } else { Join-Path $env:ProgramData 'Imperion\pipeline.config.psd1' }
    }
    if (-not (Test-Path $ConfigPath)) {
        throw "Config not found at $ConfigPath. Copy pipeline.config.example.psd1 there and fill it in (see docs/deployment)."
    }
    if (-not $SecretNamesPath) { $SecretNamesPath = Join-Path (Split-Path -Parent $ConfigPath) 'secret-names.psd1' }

    $script:ImperionConfig = Import-PowerShellDataFile -Path $ConfigPath
    $script:ImperionSecretNames = if (Test-Path $SecretNamesPath) { Import-PowerShellDataFile -Path $SecretNamesPath } else { @{} }

    if ($script:ImperionConfig.LogDirectory) { $env:IMPERION_LOG_DIR = $script:ImperionConfig.LogDirectory; $script:ImperionLogDirectory = $script:ImperionConfig.LogDirectory }
    if ($script:ImperionConfig.NpgsqlDllPath) { $env:IMPERION_NPGSQL_DLL = $script:ImperionConfig.NpgsqlDllPath; $script:ImperionNpgsqlPath = $script:ImperionConfig.NpgsqlDllPath }

    if ($SkipSecretStore) {
        Write-ImperionLog -Level Warn -Source 'context' -Message 'SecretStore SKIPPED (interim mode) — only Key-Vault-backed secrets are available this run.'
    }
    else {
        $authMode = if ($script:ImperionConfig.SecretStoreAuthentication) { $script:ImperionConfig.SecretStoreAuthentication } else { 'Password' }
        Connect-ImperionSecretStore -Authentication $authMode -CmsPasswordPath $script:ImperionConfig.CmsPasswordPath -VaultName $script:ImperionConfig.SecretVault
    }
    Write-ImperionLog -Source 'context' -Message "Context initialized (tenant $($script:ImperionConfig.PartnerTenantId))."
}
