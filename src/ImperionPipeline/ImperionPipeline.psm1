#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source every Private then Public function file. Public functions are exported
# by the manifest (FunctionsToExport); Private ones stay module-internal.
$here = Split-Path -Parent $PSCommandPath

foreach ($scope in 'Private', 'Public') {
    $dir = Join-Path $here $scope
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter '*.ps1' -Recurse |
            Sort-Object FullName |
            ForEach-Object { . $_.FullName }
    }
}
