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
    .EXAMPLE
        Import-Module ImperionPipeline; Initialize-ImperionContext
    #>
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $SecretNamesPath
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

    Connect-ImperionSecretStore -CmsPasswordPath $script:ImperionConfig.CmsPasswordPath -VaultName $script:ImperionConfig.SecretVault
    Write-ImperionLog -Source 'context' -Message "Context initialized (tenant $($script:ImperionConfig.PartnerTenantId))."
}
