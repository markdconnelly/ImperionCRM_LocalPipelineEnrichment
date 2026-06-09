<#
.SYNOPSIS
    Install the ImperionPipeline runtime dependencies machine-wide (run elevated, pwsh 7).
.DESCRIPTION
    Installs the pinned PowerShell module dependencies (SecretManagement, SecretStore, MSAL.PS)
    to -Scope AllUsers so the gMSA/service account that runs the scheduled tasks can load them,
    and pulls the Npgsql .NET driver from NuGet into %ProgramData%\Imperion\lib (the path the
    config's NpgsqlDllPath and Initialize-ImperionNpgsql both probe). Versions match
    src/ImperionPipeline/ImperionPipeline.psd1. Idempotent.

    Requires PowerShell 7 (the module is #Requires -Version 7.2). Run from an elevated session.
.EXAMPLE
    # In an elevated pwsh 7:
    .\build\Install-ImperionDependencies.ps1
.NOTES
    See docs/deployment for the full bootstrap (cert, SecretStore, gMSA).
#>
#Requires -Version 7.2
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $NpgsqlVersion = '8.0.3',
    [string] $LibDir = "$env:ProgramData\Imperion\lib"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host 'Trusting PSGallery + ensuring NuGet provider...'
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

$modules = @(
    @{ Name = 'Microsoft.PowerShell.SecretManagement'; Version = '1.1.2' }
    @{ Name = 'Microsoft.PowerShell.SecretStore'; Version = '1.0.6' }
    @{ Name = 'MSAL.PS'; Version = '4.37.0' }
)
foreach ($m in $modules) {
    if (Get-Module -ListAvailable -Name $m.Name | Where-Object Version -eq $m.Version) {
        Write-Host "  $($m.Name) $($m.Version) already present."
        continue
    }
    if ($PSCmdlet.ShouldProcess("$($m.Name) $($m.Version)", 'Install-Module -Scope AllUsers')) {
        Install-Module -Name $m.Name -RequiredVersion $m.Version -Scope AllUsers -Force -AcceptLicense
        Write-Host "  Installed $($m.Name) $($m.Version)."
    }
}

# Npgsql .NET driver -> machine lib folder (matches config NpgsqlDllPath).
if ($PSCmdlet.ShouldProcess("Npgsql $NpgsqlVersion -> $LibDir", 'Install-Package')) {
    New-Item -ItemType Directory -Force -Path $LibDir | Out-Null
    if (-not (Get-PackageSource -Name nuget.org -ErrorAction SilentlyContinue)) {
        Register-PackageSource -Name nuget.org -ProviderName NuGet -Location 'https://api.nuget.org/v3/index.json' -Trusted | Out-Null
    }
    Install-Package Npgsql -ProviderName NuGet -RequiredVersion $NpgsqlVersion -Destination $LibDir -Force | Out-Null
    Write-Host "  Pulled Npgsql $NpgsqlVersion to $LibDir."
}

Write-Host "`nVerify:"
Get-Module -ListAvailable Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore, MSAL.PS |
    Select-Object Name, Version | Format-Table -AutoSize
$dll = Get-ChildItem -Recurse $LibDir -Filter Npgsql.dll -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dll) { Write-Host "Npgsql.dll: $($dll.FullName)" } else { Write-Warning 'Npgsql.dll not found under lib dir.' }
Write-Host "`nNext: set NpgsqlDllPath in %ProgramData%\Imperion\pipeline.config.psd1 to the Npgsql.dll path above (if not the default)."
