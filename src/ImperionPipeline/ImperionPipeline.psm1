#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pre-initialize module-scope state so every function can safely READ it before
# Initialize-ImperionContext runs. Under Set-StrictMode -Version Latest, referencing an
# unset variable throws (even inside `if (-not $script:x)`), so these must exist up front.
# Initialize-ImperionContext populates config/secret-names/log-dir/npgsql-path; the caches
# lazy-fill on first use. (Get-ImperionConfig still throws its "not initialized" message
# because the value is $null, not because the variable is missing.)
$script:ImperionConfig            = $null
$script:ImperionSecretNames       = $null
$script:ImperionLogDirectory      = $null
$script:ImperionRunId             = $null
$script:ImperionNpgsqlPath        = $null
$script:ImperionSecretStoreVault  = $null
$script:ImperionTokenCache        = @{}
$script:ImperionAutotaskZoneCache = @{}

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
