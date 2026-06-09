#Requires -Modules Pester
# Hermetic tests for the operator bootstrap Initialize-ImperionUnattended. The SecretManagement/
# SecretStore cmdlets are stubbed then mocked; the security-sensitive writes are verified to be
# ShouldProcess-gated (no real vault config, CMS file, or ACL change happens).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        foreach ($name in 'Get-SecretVault', 'Register-SecretVault', 'Set-SecretStoreConfiguration') {
            if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
                New-Item -Path "function:script:$name" -Value { param() } | Out-Null
            }
        }
    }
}

Describe 'Initialize-ImperionUnattended' {
    It 'gates the vault config + CMS write behind ShouldProcess (nothing under -WhatIf)' {
        InModuleScope ImperionPipeline {
            Mock Get-Item { [pscustomobject]@{ Subject = 'CN=Imperion'; Thumbprint = 'ABC' } }
            Mock Get-SecretVault { $null }
            Mock Register-SecretVault { }
            Mock Set-SecretStoreConfiguration { }
            Mock Protect-CmsMessage { }
            Mock Test-Path { $true }
            Mock Write-Host { }

            Initialize-ImperionUnattended -CertThumbprint 'ABC' -WhatIf

            Should -Invoke Get-Item -Times 1 -ParameterFilter { $Path -like 'Cert:\LocalMachine\My\ABC*' }
            Should -Invoke Set-SecretStoreConfiguration -Times 0
            Should -Invoke Protect-CmsMessage -Times 0
        }
    }

    It 'surfaces a missing certificate (Get-Item -ErrorAction Stop)' {
        InModuleScope ImperionPipeline {
            Mock Get-Item { throw 'Cannot find certificate' }
            Mock Write-Host { }
            { Initialize-ImperionUnattended -CertThumbprint 'MISSING' -WhatIf } | Should -Throw '*certificate*'
        }
    }
}
