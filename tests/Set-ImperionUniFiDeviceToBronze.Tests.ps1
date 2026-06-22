#Requires -Modules Pester
# Hermetic test for Set-ImperionUniFiDeviceToBronze: standard envelope, projected to the
# unifi_devices column set (front-end migration 0162, #1053/#73). Mocked DB seams.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionUniFiDeviceToBronze' {
    It 'projects rows to the unifi_devices column set and change-detect upserts' {
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
                    name = 'Office Switch'; model = 'USW-24'; mac = 'AA:BB'; ip_address = '10.0.0.2'
                    site = 'Acme HQ'; status = 'ONLINE'; firmware_version = '7.1.20'; firmware_updatable = 'True'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'unifi'; external_id = 'dev-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionUniFiDeviceToBronze

            $script:captured.Table    | Should -Be 'unifi_devices'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'name', 'model', 'mac', 'ip_address', 'site', 'status',
                    'firmware_version', 'firmware_updatable', 'adopted', 'last_seen',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.adopted | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionUniFiDeviceToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ name = 'ap'; external_id = 'd'; content_hash = 'h' }
            { $row | Set-ImperionUniFiDeviceToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
