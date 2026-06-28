#Requires -Modules Pester
# Hermetic tests for Get-ImperionAzureResourceGroup + the private ConvertTo-ImperionTagString.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'ConvertTo-ImperionTagString' {
    It 'flattens a tags object to k=v; k=v' {
        InModuleScope ImperionPipeline {
            ConvertTo-ImperionTagString ([pscustomobject]@{ env = 'prod'; owner = 'mark' }) | Should -Match 'env=prod'
        }
    }
    It 'returns $null for no tags' {
        InModuleScope ImperionPipeline {
            ConvertTo-ImperionTagString $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-ImperionAzureResourceGroup' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionArmToken { 'arm-token' }
        }
    }

    It 'flattens resource groups (with tags) to the bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                , @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg1'; name = 'rg1'; location = 'eastus'; properties = [pscustomobject]@{ provisioningState = 'Succeeded' }; tags = [pscustomobject]@{ env = 'prod' } })
            }
            $rows = Get-ImperionAzureResourceGroup -SubscriptionId 'sub-1'
            $rows[0].name               | Should -Be 'rg1'
            $rows[0].provisioning_state | Should -Be 'Succeeded'
            $rows[0].subscription_id    | Should -Be 'sub-1'
            $rows[0].tags               | Should -Match 'env=prod'
            $rows[0].source             | Should -Be 'azure'
            $rows[0].external_id        | Should -Be '/subscriptions/sub-1/resourceGroups/rg1'
        }
    }

    It 'does not throw when a resource group has no tags' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest { , @([pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg2'; name = 'rg2'; location = 'eastus' }) }
            { Get-ImperionAzureResourceGroup -SubscriptionId 'sub-1' } | Should -Not -Throw
            (Get-ImperionAzureResourceGroup -SubscriptionId 'sub-1')[0].tags | Should -BeNullOrEmpty
        }
    }

    It 'queries the subscription resourcegroups path' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest { , @() }
            Get-ImperionAzureResourceGroup -SubscriptionId 'sub-9' | Out-Null
            Should -Invoke Invoke-ImperionArmRequest -Times 1 -ParameterFilter { $Path -like '/subscriptions/sub-9/resourcegroups?*' }
        }
    }
}
