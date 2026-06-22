#Requires -Modules Pester
# Hermetic test for Invoke-ImperionITGlueExport: the IT Glue request layer + DB are mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionITGlueExport' {
    It 'exports records and does not throw when a record lacks attributes' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ ITGlue = @{ BaseUri = 'https://api.itglue.com' } } }
            Mock Resolve-ImperionITGlueApiKey { 'key-value' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionDbNonQuery { 0 }
            $tables = @{}
            Mock Invoke-ImperionBronzeUpsert { $tables[$Table] = $Rows; [pscustomobject]@{ scanned = @($Rows).Count; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionITGlueRequest {
                param($Path, $ApiKey, $Method = 'GET', $Body, $Query, $BaseUri)
                if ($Path -eq 'organizations') {
                    return , @(
                        [pscustomobject]@{ id = 'o1'; type = 'organizations'; attributes = [pscustomobject]@{ name = 'Acme'; 'resource-url' = 'http://x'; 'created-at' = '2026'; 'updated-at' = '2026' } },
                        [pscustomobject]@{ id = 'o2'; type = 'organizations' }   # NO attributes -> must not throw
                    )
                }
                return , @()   # every other resource type + flexible_asset_types -> empty
            }

            { Invoke-ImperionITGlueExport } | Should -Not -Throw
            $tables.ContainsKey('itglue_export_organizations') | Should -BeTrue
            @($tables['itglue_export_organizations']).Count | Should -Be 2
            $tables['itglue_export_organizations'][0].name | Should -Be 'Acme'
            $tables['itglue_export_organizations'][1].external_id | Should -Be 'o2'
        }
    }
}
