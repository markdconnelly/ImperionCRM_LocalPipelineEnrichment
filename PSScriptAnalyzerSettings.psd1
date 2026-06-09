@{
    # Lint gate (CLAUDE.md §4). Run: Invoke-ScriptAnalyzer -Path ./src,./scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Write-Host is used intentionally for operator-facing console lines in setup scripts.
        'PSAvoidUsingWriteHost'
    )
}
