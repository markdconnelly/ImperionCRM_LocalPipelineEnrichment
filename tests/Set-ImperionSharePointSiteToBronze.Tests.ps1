#Requires -Modules Pester
# Hermetic tests for Set-ImperionSharePointSiteToBronze: standard envelope, projected to
# the exact sharepoint_sites column set (front-end migration 0078, issue #137).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionSharePointSiteToBronze' {
    It 'projects rows to the exact 0078 sharepoint_sites column set and change-detect upserts' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{
                    display_name = 'Imperion Operations'; name = 'operations'
                    web_url = 'https://imperionllc.sharepoint.com/sites/operations'
                    description = 'Internal ops hub'
                    created_date_time = '2024-01-15T10:00:00Z'
                    last_modified_date_time = '2026-06-11T22:15:00Z'
                    is_personal_site = 'false'
                    site_collection_hostname = 'imperionllc.sharepoint.com'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'
                    external_id = 'imperionllc.sharepoint.com,coll-guid-1,web-guid-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionSharePointSiteToBronze

            $script:captured.Table    | Should -Be 'sharepoint_sites'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'display_name', 'name', 'web_url', 'description',
                    'created_date_time', 'last_modified_date_time',
                    'web_template', 'is_personal_site', 'site_collection_hostname',
                    'storage_used_bytes', 'storage_quota_bytes',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.display_name        | Should -Be 'Imperion Operations'
            $projected.is_personal_site    | Should -Be 'false'
            $projected.web_template        | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $projected.storage_used_bytes  | Should -BeNullOrEmpty
            $projected.external_id         | Should -Be 'imperionllc.sharepoint.com,coll-guid-1,web-guid-1'
            ($projected.PSObject.Properties.Name -match 'file|drive|item') | Should -BeNullOrEmpty   # no file/drive/item columns, ever (0078)
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionSharePointSiteToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ display_name = 's'; external_id = 'g'; content_hash = 'h' }
            { $row | Set-ImperionSharePointSiteToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
