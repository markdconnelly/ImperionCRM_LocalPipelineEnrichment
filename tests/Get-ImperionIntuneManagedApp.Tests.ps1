#Requires -Modules Pester
# Hermetic tests for Get-ImperionIntuneManagedApp: Graph token + request mocked in module scope.
# The collector fans out managedDevices -> per-device detectedApps (issue #252, FE migration 0148).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionIntuneManagedApp' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens each per-device detected app to the 0148 bronze envelope (composite external_id)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'managedDevices' -and $Uri -notmatch 'detectedApps' } {
                , @([pscustomobject]@{ id = 'dev-1'; deviceName = 'SRV-DC1'; serialNumber = 'SN-1' })
            }
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'detectedApps' } {
                , @([pscustomobject]@{
                        id = 'app-9'; displayName = '7-Zip'; publisher = 'Igor Pavlov'
                        version = '23.01'; platform = 'windows'; sizeInByte = 1500000
                    })
            }

            $rows = @(Get-ImperionIntuneManagedApp)
            $rows.Count | Should -Be 1
            $rows[0].managed_device_id | Should -Be 'dev-1'
            $rows[0].serial_number     | Should -Be 'SN-1'
            $rows[0].device_name       | Should -Be 'SRV-DC1'
            $rows[0].app_id            | Should -Be 'app-9'
            $rows[0].display_name      | Should -Be '7-Zip'
            $rows[0].publisher         | Should -Be 'Igor Pavlov'
            $rows[0].version           | Should -Be '23.01'
            $rows[0].platform          | Should -Be 'windows'
            $rows[0].size_in_bytes     | Should -Be '1500000'   # numeric coerced to text
            $rows[0].app_type          | Should -Be 'detected'  # this feed is the detected-inventory half
            $rows[0].install_state     | Should -BeNullOrEmpty   # detectedApp carries no install state
            $rows[0].source            | Should -Be 'm365'
            $rows[0].external_id       | Should -Be 'dev-1:app-9'  # managed_device_id + app_id
        }
    }

    It 'queries detectedApps per device and tolerates a device with no apps' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'managedDevices' -and $Uri -notmatch 'detectedApps' } {
                , @(
                    [pscustomobject]@{ id = 'dev-1'; deviceName = 'A'; serialNumber = 'S1' },
                    [pscustomobject]@{ id = 'dev-2'; deviceName = 'B'; serialNumber = 'S2' }
                )
            }
            # dev-1 has one app, dev-2 has none.
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'dev-1/detectedApps' } {
                , @([pscustomobject]@{ id = 'app-1'; displayName = 'App One' })
            }
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'dev-2/detectedApps' } { , @() }

            $rows = @(Get-ImperionIntuneManagedApp)
            $rows.Count | Should -Be 1
            $rows[0].external_id | Should -Be 'dev-1:app-1'
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter { $Uri -match 'dev-1/detectedApps' }
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter { $Uri -match 'dev-2/detectedApps' }
        }
    }

    It 'skips a detectedApp missing id (StrictMode) without aborting the tenant (#374)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'managedDevices' -and $Uri -notmatch 'detectedApps' } {
                , @([pscustomobject]@{ id = 'dev-1'; deviceName = 'A'; serialNumber = 'S1' })
            }
            # First app has no id (the live failure shape); second is well-formed.
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'detectedApps' } {
                , @(
                    [pscustomobject]@{ displayName = 'Ghost'; version = '1.0' },
                    [pscustomobject]@{ id = 'app-2'; displayName = 'Real App' }
                )
            }

            # A throw here (the pre-#374 behavior) fails the test; the row count proves the skip.
            $rows = @(Get-ImperionIntuneManagedApp)
            $rows.Count | Should -Be 1
            $rows[0].external_id | Should -Be 'dev-1:app-2'
        }
    }

    It 'skips a device missing id (StrictMode) without aborting (#374)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'managedDevices' -and $Uri -notmatch 'detectedApps' } {
                , @(
                    [pscustomobject]@{ deviceName = 'NoId'; serialNumber = 'S0' },
                    [pscustomobject]@{ id = 'dev-2'; deviceName = 'B'; serialNumber = 'S2' }
                )
            }
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'dev-2/detectedApps' } {
                , @([pscustomobject]@{ id = 'app-1'; displayName = 'App One' })
            }

            $rows = @(Get-ImperionIntuneManagedApp)
            $rows.Count | Should -Be 1
            $rows[0].external_id | Should -Be 'dev-2:app-1'
        }
    }

    It 'calls per-device detectedApps on the BETA endpoint, keeping the managedDevices list on v1.0 (#369)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'managedDevices' -and $Uri -notmatch 'detectedApps' } {
                , @([pscustomobject]@{ id = 'dev-1'; deviceName = 'A'; serialNumber = 'S1' })
            }
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'detectedApps' } { , @() }

            Get-ImperionIntuneManagedApp | Out-Null

            # detectedApps only exists under beta; the device list stays v1.0.
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/beta/deviceManagement/managedDevices/dev-1/detectedApps'
            }
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices'
            }
        }
    }

    It 'collects from the requested tenant via the per-client onboarding-app token' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionIntuneManagedApp -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
