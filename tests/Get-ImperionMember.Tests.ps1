#Requires -Modules Pester
# Unit tests for the private StrictMode-safe member reader Get-ImperionMember.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMember' {
    It 'returns the value of an existing member' {
        InModuleScope ImperionPipeline {
            $o = [pscustomobject]@{ value = 42 }
            Get-ImperionMember $o 'value' | Should -Be 42
        }
    }

    It 'returns $null for a missing member instead of throwing (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            $o = [pscustomobject]@{ a = 1 }
            { Get-ImperionMember $o 'value' } | Should -Not -Throw
            Get-ImperionMember $o 'value' | Should -BeNullOrEmpty
        }
    }

    It 'reads a member name that contains a dot (e.g. @odata.nextLink)' {
        InModuleScope ImperionPipeline {
            $o = [pscustomobject]@{ '@odata.nextLink' = 'https://next' }
            Get-ImperionMember $o '@odata.nextLink' | Should -Be 'https://next'
        }
    }

    It 'returns $null when the input object itself is $null' {
        InModuleScope ImperionPipeline {
            Get-ImperionMember $null 'anything' | Should -BeNullOrEmpty
        }
    }
}
