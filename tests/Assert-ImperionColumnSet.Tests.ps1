#Requires -Modules Pester
# Hermetic tests for Assert-ImperionColumnSet, the -ColumnSet schema-drift guard (#427):
# a collector's declared column set is validated against the live table's
# information_schema.columns (via Get-ImperionSilverSchema) before any upsert, so drift
# fails fast with the table + missing columns named instead of an opaque insert failure.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Assert-ImperionColumnSet' {
    It 'passes silently when every declared column exists on the live table' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@('tenant_id', 'source', 'external_id', 'name', 'kind', 'content_hash', 'raw_payload') }

            $conn = [pscustomobject]@{}
            { Assert-ImperionColumnSet -Connection $conn -Table 'azure_resources' `
                    -ColumnSet @('name', 'kind', 'external_id', 'content_hash') } | Should -Not -Throw
            Should -Invoke Get-ImperionSilverSchema -Times 1 -ParameterFilter { $Relation -eq 'azure_resources' }
        }
    }

    It 'matches case-insensitively (PowerShell semantics; Postgres lower-cases unquoted identifiers)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@('external_id', 'display_name') }

            { Assert-ImperionColumnSet -Connection ([pscustomobject]@{}) -Table 't' `
                    -ColumnSet @('External_Id', 'DISPLAY_NAME') } | Should -Not -Throw
        }
    }

    It 'throws naming the table and every missing column when the declared set has drifted' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@('tenant_id', 'source', 'external_id', 'name', 'content_hash') }

            $act = { Assert-ImperionColumnSet -Connection ([pscustomobject]@{}) -Table 'azure_resources' `
                    -ColumnSet @('name', 'kind', 'sku_tier', 'external_id', 'content_hash') }

            $act | Should -Throw "*table 'azure_resources' is missing declared column(s): kind, sku_tier*"
            # The error also surfaces the live columns, so the fix is one read away.
            $act | Should -Throw '*Live columns: tenant_id, source, external_id, name, content_hash*'
        }
    }

    It 'throws a clear does-not-exist error when the table is absent entirely' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSilverSchema { [string[]]@() }

            { Assert-ImperionColumnSet -Connection ([pscustomobject]@{}) -Table 'not_migrated_yet' `
                    -ColumnSet @('external_id') } |
                Should -Throw "*table 'not_migrated_yet' does not exist*"
        }
    }

    It 'never creates or alters schema — it only reads catalog metadata for the one relation' {
        InModuleScope ImperionPipeline {
            $script:relationAsked = $null
            Mock Get-ImperionSilverSchema { $script:relationAsked = $Relation; [string[]]@('external_id') }

            Assert-ImperionColumnSet -Connection ([pscustomobject]@{}) -Table 'meta_pages' -ColumnSet @('external_id')

            $script:relationAsked | Should -Be 'meta_pages'
            Should -Invoke Get-ImperionSilverSchema -Times 1 -Exactly
        }
    }
}
