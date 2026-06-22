#Requires -Modules Pester
# Hermetic test for Set-ImperionIntuneManagedAppToBronze: standard envelope, projected to the
# intune_managed_apps column set (front-end migration 0148, per-device app inventory — issue #252).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionIntuneManagedAppToBronze' {
    It 'projects rows to the 0148 intune_managed_apps column set and change-detect upserts' {
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
                    managed_device_id = 'dev-1'; serial_number = 'SN-1'; device_name = 'SRV-DC1'
                    app_id = 'app-9'; display_name = '7-Zip'; publisher = 'Igor Pavlov'
                    version = '23.01'; platform = 'windows'; app_type = 'detected'
                    size_in_bytes = '1500000'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'dev-1:app-9'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionIntuneManagedAppToBronze

            $script:captured.Table    | Should -Be 'intune_managed_apps'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'managed_device_id', 'serial_number', 'device_name',
                    'app_id', 'display_name', 'publisher', 'version', 'platform',
                    'install_state', 'install_state_detail', 'app_type',
                    'size_in_bytes', 'last_modified_date_time',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.managed_device_id | Should -Be 'dev-1'
            $projected.app_id            | Should -Be 'app-9'
            $projected.app_type          | Should -Be 'detected'
            $projected.install_state     | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionIntuneManagedAppToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ display_name = 'a'; external_id = 'dev:app'; content_hash = 'h' }
            { $row | Set-ImperionIntuneManagedAppToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
