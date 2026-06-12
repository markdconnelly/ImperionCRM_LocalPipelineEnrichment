#Requires -Modules Pester
# Hermetic test for Set-ImperionIntuneManagedDeviceToBronze: standard envelope, projected to
# the PROPOSED intune_managed_devices column set (front-end migration pending, issue #75).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionIntuneManagedDeviceToBronze' {
    It 'projects rows to the proposed intune_managed_devices column set and change-detect upserts' {
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
                    device_name = 'LT-042'; os = 'Windows'; os_version = '10.0.26100'
                    compliance_state = 'compliant'; serial_number = 'SER-1'; azure_ad_device_id = 'aad-1'
                    user_principal_name = 'jane@acme.com'; last_sync_date_time = '2026-06-11T01:00:00Z'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'md-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionIntuneManagedDeviceToBronze

            $script:captured.Table    | Should -Be 'intune_managed_devices'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'device_name', 'managed_device_name', 'os', 'os_version', 'compliance_state',
                    'management_state', 'manufacturer', 'model', 'serial_number', 'imei',
                    'wifi_mac_address', 'azure_ad_device_id', 'user_principal_name',
                    'user_display_name', 'email_address', 'ownership', 'enrolled_date_time',
                    'last_sync_date_time', 'is_encrypted', 'device_category',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.compliance_state   | Should -Be 'compliant'
            $projected.azure_ad_device_id | Should -Be 'aad-1'
            $projected.model              | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionIntuneManagedDeviceToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ device_name = 'd'; external_id = 'md'; content_hash = 'h' }
            { $row | Set-ImperionIntuneManagedDeviceToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
