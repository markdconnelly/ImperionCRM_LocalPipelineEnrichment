#Requires -Modules Pester
# Hermetic tests for Get-ImperionCloudResource (epic #201 / #216): ARM token + requests mocked,
# routed by path (subscription list / per-sub resourcegroups / per-sub resources). No live ARM.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionCloudResource' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionArmToken { 'arm-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '/resourcegroups\?' {
                        return @([pscustomobject]@{
                                id = '/subscriptions/sub-1/resourceGroups/rg1'
                                name = 'rg1'; location = 'eastus'
                                properties = [pscustomobject]@{ provisioningState = 'Succeeded' }
                                tags = [pscustomobject]@{ env = 'prod' }
                            })
                    }
                    '/resources\?' {
                        return @([pscustomobject]@{
                                id = '/subscriptions/sub-1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/acct1'
                                name = 'acct1'; type = 'Microsoft.Storage/storageAccounts'
                                location = 'eastus'; kind = 'StorageV2'
                                sku = [pscustomobject]@{ name = 'Standard_LRS' }
                                tags = [pscustomobject]@{ env = 'prod' }
                            })
                    }
                    '/subscriptions\?' {
                        return @([pscustomobject]@{
                                subscriptionId = 'sub-1'; displayName = 'Client Prod'
                                state = 'Enabled'; tenantId = 'client-tenant'
                            })
                    }
                    default { return @() }
                }
            }
        }
    }

    It 'emits one subscription, one resource-group, and one resource row, each entity-stamped' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionCloudResource -TenantId 'client-tenant')
            $rows.Count | Should -Be 3
            ($rows | Where-Object entity -eq 'subscriptions').Count   | Should -Be 1
            ($rows | Where-Object entity -eq 'resource_groups').Count | Should -Be 1
            ($rows | Where-Object entity -eq 'resources').Count       | Should -Be 1
        }
    }

    It 'stamps the source azure_arm and the owning tenant on every row (per-tenant isolation)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionCloudResource -TenantId 'client-tenant')
            ($rows | ForEach-Object source).ForEach({ $_ | Should -Be 'azure_arm' })
            ($rows | ForEach-Object tenant_id).ForEach({ $_ | Should -Be 'client-tenant' })
        }
    }

    It 'uses the ARM resource id as the resource external_id and parses the resource group' {
        InModuleScope ImperionPipeline {
            $resource = @(Get-ImperionCloudResource -TenantId 'client-tenant') | Where-Object entity -eq 'resources'
            $resource.name           | Should -Be 'acct1'
            $resource.type           | Should -Be 'Microsoft.Storage/storageAccounts'
            $resource.sku            | Should -Be 'Standard_LRS'
            $resource.resource_group | Should -Be 'rg1'
            $resource.tags           | Should -Match 'env=prod'
            $resource.external_id    | Should -Be '/subscriptions/sub-1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/acct1'
        }
    }

    It 'authenticates against the supplied client tenant (fail-closed per-tenant auth)' {
        InModuleScope ImperionPipeline {
            Get-ImperionCloudResource -TenantId 'client-9' | Out-Null
            Should -Invoke Get-ImperionArmToken -Times 1 -ParameterFilter { $TenantId -eq 'client-9' }
        }
    }

    It 'defaults to the partner tenant when no TenantId is supplied (dormant-safe fallback)' {
        InModuleScope ImperionPipeline {
            Get-ImperionCloudResource | Out-Null
            Should -Invoke Get-ImperionArmToken -Times 1 -ParameterFilter { $TenantId -eq 'partner' }
        }
    }

    It 'does not throw when a resource has no tags, sku, or kind' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '/resourcegroups\?' { return @() }
                    '/resources\?' { return @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg2/providers/p/r'; name = 'r'; type = 't'; location = 'eastus' }) }
                    '/subscriptions\?' { return @([pscustomobject]@{ subscriptionId = 'sub-1'; displayName = 'd'; state = 'Enabled'; tenantId = 't' }) }
                    default { return @() }
                }
            }
            { Get-ImperionCloudResource -TenantId 'client-tenant' } | Should -Not -Throw
        }
    }
}
