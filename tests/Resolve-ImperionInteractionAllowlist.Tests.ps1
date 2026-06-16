#Requires -Modules Pester
# Hermetic tests for the config-driven allowlist resolver (reads a temp json; no live config).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionInteractionAllowlist' {
    BeforeEach {
        $script:tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("imperion-allowlist-{0}.json" -f [guid]::NewGuid())
    }
    AfterEach {
        if (Test-Path -LiteralPath $script:tempFile) { Remove-Item -LiteralPath $script:tempFile -Force }
    }

    It 'reads principal UPNs from the json and lower-cases them' {
        $json = '{ "principals": [ { "upn": "Derek@ImperionLLC.com", "displayName": "Derek" }, { "upn": "mark@imperionllc.com" } ] }'
        Set-Content -LiteralPath $script:tempFile -Value $json
        InModuleScope ImperionPipeline -Parameters @{ Path = $script:tempFile } {
            param($Path)
            $result = Resolve-ImperionInteractionAllowlist -Path $Path
            @($result).Count | Should -Be 2
            $result | Should -Contain 'derek@imperionllc.com'
            $result | Should -Contain 'mark@imperionllc.com'
        }
    }

    It 'returns $null when the file is absent (dormant/fail-closed)' {
        InModuleScope ImperionPipeline {
            Resolve-ImperionInteractionAllowlist -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist-imperion.json') | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the json has no usable principal' {
        $json = '{ "principals": [ { "displayName": "no upn here" }, { "upn": "" } ] }'
        Set-Content -LiteralPath $script:tempFile -Value $json
        InModuleScope ImperionPipeline -Parameters @{ Path = $script:tempFile } {
            param($Path)
            Resolve-ImperionInteractionAllowlist -Path $Path | Should -BeNullOrEmpty
        }
    }

    It 'de-duplicates repeated principals' {
        $json = '{ "principals": [ { "upn": "derek@imperionllc.com" }, { "upn": "DEREK@imperionllc.com" } ] }'
        Set-Content -LiteralPath $script:tempFile -Value $json
        InModuleScope ImperionPipeline -Parameters @{ Path = $script:tempFile } {
            param($Path)
            @(Resolve-ImperionInteractionAllowlist -Path $Path).Count | Should -Be 1
        }
    }

    It 'throws on a malformed json (operator error, not silent)' {
        Set-Content -LiteralPath $script:tempFile -Value '{ not valid json'
        InModuleScope ImperionPipeline -Parameters @{ Path = $script:tempFile } {
            param($Path)
            { Resolve-ImperionInteractionAllowlist -Path $Path } | Should -Throw
        }
    }
}
