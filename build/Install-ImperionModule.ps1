<#
.SYNOPSIS
    Install the ImperionPipeline module onto this PC and seed machine config (ADR-0007).
.DESCRIPTION
    Copies src/ImperionPipeline to a versioned folder under a PSModulePath location so it
    imports by name (Import-Module ImperionPipeline). Seeds config templates into
    %ProgramData%\Imperion if absent (the real config lives outside the module so updates
    never clobber it). Run as administrator for -Scope AllUsers.
.PARAMETER Scope
    AllUsers (Program Files modules) or CurrentUser. Default AllUsers.
.EXAMPLE
    .\build\Install-ImperionModule.ps1 -Scope AllUsers
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('AllUsers', 'CurrentUser')][string] $Scope = 'AllUsers'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleSrc = Join-Path $repoRoot 'src\ImperionPipeline'
$manifest = Import-PowerShellDataFile (Join-Path $moduleSrc 'ImperionPipeline.psd1')
$version = $manifest.ModuleVersion

$baseModulePath = if ($Scope -eq 'AllUsers') {
    Join-Path $env:ProgramFiles 'PowerShell\Modules'
}
else {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
}
$dest = Join-Path $baseModulePath "ImperionPipeline\$version"

if ($PSCmdlet.ShouldProcess($dest, 'Install ImperionPipeline module')) {
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $moduleSrc '*') -Destination $dest -Recurse -Force
    Write-Host "Installed ImperionPipeline $version -> $dest"
}

# Seed machine config (do not overwrite real config).
$configDir = Join-Path $env:ProgramData 'Imperion'
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Force -Path $configDir | Out-Null }
foreach ($f in 'pipeline.config', 'secret-names') {
    $real = Join-Path $configDir "$f.psd1"
    $example = Join-Path $repoRoot "config\$f.example.psd1"
    if (-not (Test-Path $real) -and (Test-Path $example) -and $PSCmdlet.ShouldProcess($real, 'Seed config template')) {
        Copy-Item $example $real
        Write-Host "Seeded $real (edit before first run)."
    }
}

Write-Host "`nNext: edit $configDir\pipeline.config.psd1, run Initialize-ImperionUnattended, add secrets, then Register-ImperionTask."
Write-Host "Verify: Import-Module ImperionPipeline; Get-Command -Module ImperionPipeline"
