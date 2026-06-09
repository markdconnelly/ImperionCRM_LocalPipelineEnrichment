#Requires -Modules Pester
# Unit tests for the private Get-ImperionPolicyCatalog (shared policy-type -> table map).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPolicyCatalog' {
    It 'returns the five posture policy types with unique keys' {
        InModuleScope ImperionPipeline {
            $cat = Get-ImperionPolicyCatalog
            $cat.Count | Should -Be 5
            ($cat.Key | Sort-Object -Unique).Count | Should -Be 5
            $cat.Key | Should -Contain 'conditional-access'
            $cat.Key | Should -Contain 'defender-xdr'
        }
    }

    It 'each entry has Key/Source/Observed/Golden and golden tables end in _golden' {
        InModuleScope ImperionPipeline {
            foreach ($p in Get-ImperionPolicyCatalog) {
                $p.Key      | Should -Not -BeNullOrEmpty
                $p.Source   | Should -Not -BeNullOrEmpty
                $p.Observed | Should -Not -BeNullOrEmpty
                $p.Golden   | Should -Match '_golden$'
            }
        }
    }
}
