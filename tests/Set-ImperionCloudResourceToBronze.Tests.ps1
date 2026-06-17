#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionCloudResourceToBronze (multi-table router over
# Invoke-ImperionBronzePost; epic #201 / #216). No DB; the upsert + logging are mocked in
# module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionCloudResourceToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
        }
    }

    It 'routes subscription / resource-group / resource rows to their cloud_* tables by the entity discriminator' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured[$Table] = $Rows; [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 } }

            $sub = [pscustomobject]@{ entity = 'subscriptions'; display_name = 'Client Prod'; state = 'Enabled'; sub_tenant_id = 'client-tenant'; tenant_id = 'client-tenant'; source = 'azure_arm'; external_id = 'sub-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h1'; strayField = 'drop' }
            $rg  = [pscustomobject]@{ entity = 'resource_groups'; name = 'rg1'; location = 'eastus'; subscription_id = 'sub-1'; provisioning_state = 'Succeeded'; tags = 'env=prod'; tenant_id = 'client-tenant'; source = 'azure_arm'; external_id = '/subscriptions/sub-1/resourceGroups/rg1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h2' }
            $res = [pscustomobject]@{ entity = 'resources'; name = 'acct1'; type = 'Microsoft.Storage/storageAccounts'; location = 'eastus'; kind = 'StorageV2'; sku = 'Standard_LRS'; resource_group = 'rg1'; subscription_id = 'sub-1'; tags = 'env=prod'; tenant_id = 'client-tenant'; source = 'azure_arm'; external_id = '/subscriptions/sub-1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/acct1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h3' }

            $tally = @($sub, $rg, $res) | Set-ImperionCloudResourceToBronze -Confirm:$false
            $tally.inserted | Should -Be 3

            $captured.Keys | Should -Contain 'cloud_subscriptions'
            $captured.Keys | Should -Contain 'cloud_resource_groups'
            $captured.Keys | Should -Contain 'cloud_resources'

            # The entity discriminator and any stray field are projected away; flat columns survive.
            $captured['cloud_subscriptions'][0].display_name | Should -Be 'Client Prod'
            $captured['cloud_subscriptions'][0].PSObject.Properties.Name | Should -Not -Contain 'strayField'
            $captured['cloud_subscriptions'][0].PSObject.Properties.Name | Should -Not -Contain 'entity'
            $captured['cloud_resources'][0].type           | Should -Be 'Microsoft.Storage/storageAccounts'
            $captured['cloud_resources'][0].resource_group | Should -Be 'rg1'
            $captured['cloud_resources'][0].external_id     | Should -Be '/subscriptions/sub-1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/acct1'
        }
    }

    It 'fails loudly on an unknown entity (never invents a table)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $bad = [pscustomobject]@{ entity = 'unicorns'; external_id = 'x' }
            { $bad | Set-ImperionCloudResourceToBronze -Confirm:$false } | Should -Throw '*unknown cloud entity*'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionCloudResourceToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ entity = 'resources'; name = 'r'; tenant_id = 't'; source = 'azure_arm'; external_id = 'rid'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $row | Set-ImperionCloudResourceToBronze -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
