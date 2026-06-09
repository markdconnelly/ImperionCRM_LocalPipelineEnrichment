#Requires -Modules Pester
# Unit tests for the private flatten helpers Get-ImperionPropertyPath and Format-ImperionScalar.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPropertyPath' {
    It 'resolves a nested dotted path on objects' {
        InModuleScope ImperionPipeline {
            $o = [pscustomobject]@{ a = [pscustomobject]@{ b = [pscustomobject]@{ c = 42 } } }
            Get-ImperionPropertyPath -InputObject $o -Path 'a.b.c' | Should -Be 42
        }
    }

    It 'returns $null (no throw) on a missing hop' {
        InModuleScope ImperionPipeline {
            $o = [pscustomobject]@{ a = [pscustomobject]@{ x = 1 } }
            { Get-ImperionPropertyPath -InputObject $o -Path 'a.b.c' } | Should -Not -Throw
            Get-ImperionPropertyPath -InputObject $o -Path 'a.b.c' | Should -BeNullOrEmpty
        }
    }

    It 'supports dictionary (hashtable) hops' {
        InModuleScope ImperionPipeline {
            $o = @{ a = @{ b = 'deep' } }
            Get-ImperionPropertyPath -InputObject $o -Path 'a.b' | Should -Be 'deep'
            Get-ImperionPropertyPath -InputObject $o -Path 'a.missing' | Should -BeNullOrEmpty
        }
    }

    It 'returns an array hop as-is' {
        InModuleScope ImperionPipeline {
            $o = [pscustomobject]@{ tags = @('a', 'b') }
            (Get-ImperionPropertyPath -InputObject $o -Path 'tags').Count | Should -Be 2
        }
    }
}

Describe 'Format-ImperionScalar' {
    It 'passes null through as null' {
        InModuleScope ImperionPipeline { (Format-ImperionScalar -Value $null) | Should -BeNullOrEmpty }
    }
    It 'formats datetime as ISO 8601 round-trip' {
        InModuleScope ImperionPipeline {
            $d = [datetime]'2026-06-09T12:34:56Z'
            (Format-ImperionScalar -Value $d) | Should -Match '^2026-06-09T'
        }
    }
    It 'lowercases booleans' {
        InModuleScope ImperionPipeline {
            (Format-ImperionScalar -Value $true) | Should -Be 'true'
            (Format-ImperionScalar -Value $false) | Should -Be 'false'
        }
    }
    It 'joins arrays with the standard delimiter' {
        InModuleScope ImperionPipeline { (Format-ImperionScalar -Value @('a', 'b', 'c')) | Should -Be 'a; b; c' }
    }
    It 'serializes a nested object to compact JSON' {
        InModuleScope ImperionPipeline {
            $obj = [pscustomobject]@{ city = 'NYC'; zip = '10001' }
            (Format-ImperionScalar -Value $obj) | Should -Match '"city":"NYC"'
        }
    }
    It 'passes a plain string through unchanged' {
        InModuleScope ImperionPipeline { (Format-ImperionScalar -Value 'hello') | Should -Be 'hello' }
    }
}
