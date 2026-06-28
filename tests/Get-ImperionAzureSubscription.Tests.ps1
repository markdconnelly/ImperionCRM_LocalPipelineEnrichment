#Requires -Modules Pester
# Hermetic tests for Get-ImperionAzureSubscription: ARM token + request mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAzureSubscription' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionArmToken { 'arm-token' }
        }
    }

    It 'flattens subscriptions to the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                , @([pscustomobject]@{ subscriptionId = 'sub-1'; displayName = 'Prod'; state = 'Enabled'; tenantId = 'tid'; subscriptionPolicies = [pscustomobject]@{ quotaId = 'PayAsYouGo_2014-09-01' } })
            }
            $rows = Get-ImperionAzureSubscription
            $rows[0].display_name | Should -Be 'Prod'
            $rows[0].state        | Should -Be 'Enabled'
            $rows[0].quota_id     | Should -Be 'PayAsYouGo_2014-09-01'
            $rows[0].source       | Should -Be 'azure'
            $rows[0].external_id  | Should -Be 'sub-1'
        }
    }

    It 'does not throw when a subscription omits subscriptionPolicies' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest { , @([pscustomobject]@{ subscriptionId = 'sub-2'; displayName = 'Bare'; state = 'Enabled' }) }
            { Get-ImperionAzureSubscription } | Should -Not -Throw
            (Get-ImperionAzureSubscription)[0].quota_id | Should -BeNullOrEmpty
        }
    }

    It 'requests the subscriptions ARM path' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest { , @() }
            Get-ImperionAzureSubscription | Out-Null
            Should -Invoke Invoke-ImperionArmRequest -Times 1 -ParameterFilter { $Path -like '/subscriptions?*' }
        }
    }
}
