#Requires -Modules Pester
# Hermetic test for Set-ImperionIntuneManagedAppToBronze: standard envelope, projected to
# the PROPOSED intune_managed_apps column set (front-end migration pending, ImperionCRM #261).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionIntuneManagedAppToBronze' {
    It 'projects rows to the proposed intune_managed_apps column set and change-detect upserts' {
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
                    app_type = 'win32LobApp'; display_name = '7-Zip'; publisher = 'Igor Pavlov'
                    publishing_state = 'published'; is_featured = 'true'; is_assigned = 'true'
                    version = '23.01'; last_modified_date_time = '2026-06-11T01:00:00Z'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'app-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionIntuneManagedAppToBronze

            $script:captured.Table    | Should -Be 'intune_managed_apps'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'app_type', 'display_name', 'description', 'publisher', 'publishing_state',
                    'is_featured', 'is_assigned', 'version', 'owner', 'developer', 'notes',
                    'information_url', 'privacy_information_url', 'dependent_app_count',
                    'superseding_app_count', 'superseded_app_count', 'created_date_time',
                    'last_modified_date_time',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.publishing_state | Should -Be 'published'
            $projected.app_type         | Should -Be 'win32LobApp'
            $projected.owner            | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionIntuneManagedAppToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ display_name = 'a'; external_id = 'app'; content_hash = 'h' }
            { $row | Set-ImperionIntuneManagedAppToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
