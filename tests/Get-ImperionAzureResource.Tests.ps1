#Requires -Modules Pester
# Hermetic tests for Get-ImperionAzureResource: ARM token + request mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAzureResource' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionArmToken { 'arm-token' }
        }
    }

    It 'flattens resources, parses the resource group from the id, and joins tags' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                , @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/acct1'; name = 'acct1'; type = 'Microsoft.Storage/storageAccounts'; location = 'eastus'; sku = [pscustomobject]@{ name = 'Standard_LRS' }; tags = [pscustomobject]@{ env = 'prod' } })
            }
            $rows = Get-ImperionAzureResource -SubscriptionId 'sub-1'
            $rows[0].name           | Should -Be 'acct1'
            $rows[0].type           | Should -Be 'Microsoft.Storage/storageAccounts'
            $rows[0].sku            | Should -Be 'Standard_LRS'
            $rows[0].resource_group | Should -Be 'rg1'
            $rows[0].tags           | Should -Match 'env=prod'
            $rows[0].source         | Should -Be 'azure'
        }
    }

    It 'does not throw when a resource has no tags or sku' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest { , @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg2/providers/p/r'; name = 'r'; type = 't'; location = 'eastus' }) }
            { Get-ImperionAzureResource -SubscriptionId 'sub-1' } | Should -Not -Throw
            (Get-ImperionAzureResource -SubscriptionId 'sub-1')[0].resource_group | Should -Be 'rg2'
        }
    }

    It 'queries the subscription resources path' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest { , @() }
            Get-ImperionAzureResource -SubscriptionId 'sub-9' | Out-Null
            Should -Invoke Invoke-ImperionArmRequest -Times 1 -ParameterFilter { $Path -like '/subscriptions/sub-9/resources?*' }
        }
    }
}
