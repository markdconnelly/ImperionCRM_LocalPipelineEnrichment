#Requires -Modules Pester
# Tests for the private Initialize-ImperionNpgsql. Npgsql is not installed in CI, so the
# error path (no loadable assembly) is what we assert.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Initialize-ImperionNpgsql' {
    It 'throws an actionable error when no Npgsql assembly can be loaded' {
        InModuleScope ImperionPipeline {
            # No type loaded, no configured path, no env DLL, no module lib\Npgsql.dll in CI.
            $script:ImperionNpgsqlPath = $null
            $hadEnv = $env:IMPERION_NPGSQL_DLL
            Remove-Item Env:\IMPERION_NPGSQL_DLL -ErrorAction SilentlyContinue
            try {
                if ('Npgsql.NpgsqlConnection' -as [type]) {
                    Set-ItResult -Skipped -Because 'Npgsql is already loaded in this session'
                    return
                }
                { Initialize-ImperionNpgsql } | Should -Throw '*Npgsql not available*'
            }
            finally { if ($hadEnv) { $env:IMPERION_NPGSQL_DLL = $hadEnv } }
        }
    }
}
