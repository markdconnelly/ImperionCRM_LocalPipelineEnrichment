@{
    # Lint gate (CLAUDE.md §4). Run: Invoke-ScriptAnalyzer -Path ./src,./scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Write-Host is used intentionally for operator-facing console lines in setup scripts.
        'PSAvoidUsingWriteHost',
        # pwsh-7-only module (#Requires -Version 7.2): UTF-8 without BOM is the correct, intended
        # encoding. A BOM is a Windows-PowerShell-5.1 concern that doesn't apply here, and several
        # files carry intentional Unicode (§, →) in comment-based help.
        'PSUseBOMForUnicodeEncodedFile',
        # The module deliberately uses collective nouns for functions that operate on/return sets
        # (Join-ImperionValues, Get-ImperionSecretNames, …); some are public API in the manifest.
        'PSUseSingularNouns'
    )
}
