#Requires -Modules Pester
# Hermetic test for Get-ImperionSemanticDrift: live schema + concept parsing are mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionSemanticDrift' {
    It 'classifies in-sync when documented columns match the live relation' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@('id', 'name') }
            Mock Get-ImperionOkfConcept { [pscustomobject]@{ Exists = $true; Columns = @('id', 'name'); Timestamp = 't' } }
            $r = Get-ImperionSemanticDrift -BundlePath 'X' -Concept 'account' -Connection ([pscustomobject]@{})
            $r.status | Should -Be 'in-sync'
            $r.added_columns.Count | Should -Be 0
            $r.removed_columns.Count | Should -Be 0
        }
    }

    It 'flags drift with added (live, undocumented) and removed (documented, gone) deltas' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@('id', 'name', 'health_score') }
            Mock Get-ImperionOkfConcept { [pscustomobject]@{ Exists = $true; Columns = @('id', 'name', 'legacy_col'); Timestamp = 't' } }
            $r = Get-ImperionSemanticDrift -BundlePath 'X' -Concept 'account' -Connection ([pscustomobject]@{})
            $r.status | Should -Be 'drift'
            $r.added_columns | Should -Be @('health_score')
            $r.removed_columns | Should -Be @('legacy_col')
        }
    }

    It 'flags missing-concept when the live relation exists but the file does not' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@('id') }
            Mock Get-ImperionOkfConcept { [pscustomobject]@{ Exists = $false; Columns = @(); Timestamp = $null } }
            (Get-ImperionSemanticDrift -BundlePath 'X' -Concept 'account' -Connection ([pscustomobject]@{})).status | Should -Be 'missing-concept'
        }
    }

    It 'flags orphaned-concept when the file exists but the live relation is gone' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@() }
            Mock Get-ImperionOkfConcept { [pscustomobject]@{ Exists = $true; Columns = @('id'); Timestamp = 't' } }
            (Get-ImperionSemanticDrift -BundlePath 'X' -Concept 'account' -Connection ([pscustomobject]@{})).status | Should -Be 'orphaned-concept'
        }
    }

    It 'evaluates the whole catalog when no concept is specified' {
        InModuleScope ImperionPipeline {
            $count = (Get-ImperionSemanticCatalog).Count
            Mock Get-ImperionSilverSchema { [string[]]@('id') }
            Mock Get-ImperionOkfConcept { [pscustomobject]@{ Exists = $true; Columns = @('id'); Timestamp = 't' } }
            (Get-ImperionSemanticDrift -BundlePath 'X' -Connection ([pscustomobject]@{})).Count | Should -Be $count
        }
    }
}
