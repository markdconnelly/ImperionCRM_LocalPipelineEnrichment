#Requires -Modules Pester
# Hermetic test for Invoke-ImperionAzureInventorySync: ARM + DB mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionAzureInventorySync' {
    It 'does not throw and flattens a resource that has no tags or sku' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionArmToken { 'arm-token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            $tables = @{}
            Mock Invoke-ImperionBronzeUpsert { $tables[$Table] = $Rows; [pscustomobject]@{ scanned = @($Rows).Count; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionArmRequest {
                if ($Path -match '/subscriptions\?') { return , @([pscustomobject]@{ subscriptionId = 'sub1'; displayName = 'S'; tenantId = 't' }) }
                if ($Path -match 'resourcegroups') { return , @([pscustomobject]@{ name = 'rg1'; location = 'eastus'; properties = [pscustomobject]@{ provisioningState = 'Succeeded' } }) }
                if ($Path -match '/resources\?') { return , @([pscustomobject]@{ name = 'r1'; type = 'Microsoft.Storage/accounts'; location = 'eastus'; id = '/subscriptions/sub1/resourceGroups/rg1/providers/p/r1'; kind = 'k' }) }
                return , @()
            }

            { Invoke-ImperionAzureInventorySync } | Should -Not -Throw

            $resource = $tables['azure_resources'][0]
            $resource.tags           | Should -BeNullOrEmpty   # no tags -> empty, not a throw
            $resource.resource_group | Should -Be 'rg1'         # parsed from id via $rgFromId
        }
    }

    It 'joins resource tags into the flat cell when present' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionArmToken { 'arm-token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            $tables = @{}
            Mock Invoke-ImperionBronzeUpsert { $tables[$Table] = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionArmRequest {
                if ($Path -match '/subscriptions\?') { return , @([pscustomobject]@{ subscriptionId = 'sub1'; displayName = 'S'; tenantId = 't' }) }
                if ($Path -match '/resources\?') { return , @([pscustomobject]@{ name = 'r1'; type = 't'; location = 'eastus'; id = '/subscriptions/sub1/resourceGroups/rg1/providers/p/r1'; tags = [pscustomobject]@{ env = 'prod'; owner = 'mark' } }) }
                return , @()
            }
            Invoke-ImperionAzureInventorySync
            $tables['azure_resources'][0].tags | Should -Match 'env=prod'
        }
    }
}
