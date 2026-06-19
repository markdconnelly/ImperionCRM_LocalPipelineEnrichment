#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionCloudAssetMerge + ConvertTo-ImperionCloudAssetCategory:
# ShouldProcess gating, the ON CONFLICT upsert idempotency contract, null-account retention,
# and the namespace→category map parity (issue #241; the on-prem twin of the cloud Pipeline's
# mergeCloudAssetSources, front-end migration 0139 / merge-cloud-asset.ts).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'ConvertTo-ImperionCloudAssetCategory' {
    It 'maps known Microsoft.<namespace> types to their pinned category' {
        InModuleScope ImperionPipeline {
            ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.Compute/virtualMachines' | Should -Be 'compute'
            ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.Storage/storageAccounts' | Should -Be 'storage'
            ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.Sql/servers'              | Should -Be 'database'
            ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.Network/virtualNetworks'  | Should -Be 'network'
            ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.KeyVault/vaults'          | Should -Be 'security'
            ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.Web/sites'                | Should -Be 'web'
        }
    }

    It 'is case-insensitive on the namespace and strips the Microsoft. prefix' {
        InModuleScope ImperionPipeline {
            ConvertTo-ImperionCloudAssetCategory -NativeType 'MICROSOFT.COMPUTE/disks' | Should -Be 'compute'
            ConvertTo-ImperionCloudAssetCategory -NativeType 'compute/foo'             | Should -Be 'compute'
        }
    }

    It 'falls through to other for unknown / empty / malformed types' {
        InModuleScope ImperionPipeline {
            ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.Whatever/things' | Should -Be 'other'
            ConvertTo-ImperionCloudAssetCategory -NativeType ''                          | Should -Be 'other'
            ConvertTo-ImperionCloudAssetCategory -NativeType $null                       | Should -Be 'other'
            ConvertTo-ImperionCloudAssetCategory -NativeType 'garbage'                   | Should -Be 'other'
        }
    }
}

Describe 'Invoke-ImperionCloudAssetMerge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
        }
    }

    It 'honors -WhatIf: no connection, no read, no write' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 0 }
            Invoke-ImperionCloudAssetMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbQuery -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    It 'no bronze rows -> clean no-op (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 1 }
            $r = Invoke-ImperionCloudAssetMerge -Confirm:$false
            $r.resources | Should -Be 0
            $r.merged | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    Context 'merge contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                Mock Invoke-ImperionDbQuery {
                    @(
                        [pscustomobject]@{ external_id = '/sub/1/vm-a'; name = 'vm-a'; type = 'Microsoft.Compute/virtualMachines'; location = 'eastus'; sku = 'Standard_D2'; resource_group = 'rg1'; subscription_id = 'sub1'; tags = '{"env":"prod"}'; tenant_id = 't1'; source = 'azure_arm'; collected_at = '2026-06-18T00:00:00Z'; account_id = 'acc-1' }
                        [pscustomobject]@{ external_id = '/sub/1/sa-b'; name = 'sa-b'; type = 'Microsoft.Storage/storageAccounts'; location = 'eastus'; sku = $null; resource_group = 'rg1'; subscription_id = 'sub1'; tags = $null; tenant_id = 't1'; source = 'azure_arm'; collected_at = 'junk'; account_id = $null }
                    )
                }
                $script:capturedSql = $null
                $script:capturedParams = [System.Collections.Generic.List[hashtable]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:capturedSql = $Sql; $script:capturedParams.Add($Parameters); 1 }
            }
        }

        It 'upserts one cloud_asset per bronze row and returns the tally' {
            InModuleScope ImperionPipeline {
                $r = Invoke-ImperionCloudAssetMerge -Confirm:$false
                $r.resources | Should -Be 2
                $r.merged | Should -Be 2
                $r.failed | Should -Be 0
                Should -Invoke Invoke-ImperionDbNonQuery -Times 2
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Cloud asset merge complete' }
            }
        }

        It 'is an idempotent ON CONFLICT (provider, external_id) upsert into cloud_asset' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionCloudAssetMerge -Confirm:$false | Out-Null
                $script:capturedSql | Should -Match 'INSERT INTO cloud_asset'
                $script:capturedSql | Should -Match "'azure'"
                $script:capturedSql | Should -Match 'ON CONFLICT \(provider, external_id\) DO UPDATE SET'
                $script:capturedSql | Should -Match '@category::cloud_asset_category'
            }
        }

        It 'normalizes the category and keeps null-account rows (CMDB filters nulls, not the merge)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionCloudAssetMerge -Confirm:$false | Out-Null
                $vm = $script:capturedParams | Where-Object { $_.external_id -eq '/sub/1/vm-a' }
                $sa = $script:capturedParams | Where-Object { $_.external_id -eq '/sub/1/sa-b' }
                $vm.category | Should -Be 'compute'
                $vm.account_id | Should -Be 'acc-1'
                $sa.category | Should -Be 'storage'
                # unmapped tenant -> NULL account_id, row still upserted
                $sa.account_id | Should -BeNullOrEmpty
            }
        }

        It 'regex-guards the bronze text collected_at (junk -> null -> COALESCE now())' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionCloudAssetMerge -Confirm:$false | Out-Null
                $script:capturedSql | Should -Match 'COALESCE\(@last_seen_at::timestamptz, now\(\)\)'
                $vm = $script:capturedParams | Where-Object { $_.external_id -eq '/sub/1/vm-a' }
                $sa = $script:capturedParams | Where-Object { $_.external_id -eq '/sub/1/sa-b' }
                $vm.last_seen_at | Should -Be '2026-06-18T00:00:00Z'
                $sa.last_seen_at | Should -BeNullOrEmpty   # 'junk' fails the regex -> null
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionCloudAssetMerge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}
