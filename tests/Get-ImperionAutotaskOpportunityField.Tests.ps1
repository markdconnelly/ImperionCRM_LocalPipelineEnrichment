#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionAutotaskOpportunityField (#1325): hits the Autotask
# entityInformation/fields endpoint, flattens field metadata only, NEVER queries records.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskOpportunityField' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock Get-ImperionAutotaskContext {
                [pscustomobject]@{
                    Headers = @{ ApiIntegrationCode = 'x'; UserName = 'u'; Secret = 's'; 'Content-Type' = 'application/json' }
                    ApiBase = 'https://webservices15.autotask.net/atservicesrest/V1.0'
                }
            }
            $script:capturedUri = $null
            $script:capturedMethod = $null
            Mock Invoke-ImperionRestWithRetry {
                $script:capturedUri = $Uri
                $script:capturedMethod = $Method
                [pscustomobject]@{ Status = 200; Headers = @{}; Body = [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'amount';       dataType = 'decimal'; isRequired = $true;  isQueryable = $true; isReadOnly = $false; isPickList = $false; length = 0;  picklistValues = @() }
                    [pscustomobject]@{ name = 'stage';        dataType = 'integer'; isRequired = $true;  isQueryable = $true; isReadOnly = $false; isPickList = $true;  length = 0;  picklistValues = @(
                        [pscustomobject]@{ value = '1'; label = 'Prospecting'; isActive = $true }
                        [pscustomobject]@{ value = '9'; label = 'Retired';     isActive = $false }
                    ) }
                ) } }
            }
        }
    }

    It 'calls the entityInformation/fields endpoint with GET (never /query — no record data)' {
        InModuleScope ImperionPipeline {
            Get-ImperionAutotaskOpportunityField | Out-Null
            $script:capturedUri    | Should -Match 'Opportunities/entityInformation/fields$'
            $script:capturedUri    | Should -Not -Match '/query'
            $script:capturedMethod | Should -Be 'GET'
        }
    }

    It 'flattens field metadata (name/dataType/isPickList) into a table' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionAutotaskOpportunityField)
            $rows.Count | Should -Be 2
            ($rows | Where-Object name -eq 'amount').dataType | Should -Be 'decimal'
            ($rows | Where-Object name -eq 'stage').isPickList | Should -BeTrue
        }
    }

    It 'emits ACTIVE picklist labels only (value=label), dropping inactive entries' {
        InModuleScope ImperionPipeline {
            $stage = @(Get-ImperionAutotaskOpportunityField) | Where-Object name -eq 'stage'
            $stage.picklist | Should -Match '1=Prospecting'
            $stage.picklist | Should -Not -Match 'Retired'
        }
    }

    It 'honors -Entity for a related entity probe' {
        InModuleScope ImperionPipeline {
            Get-ImperionAutotaskOpportunityField -Entity 'OpportunityCategories' | Out-Null
            $script:capturedUri | Should -Match 'OpportunityCategories/entityInformation/fields$'
        }
    }

    It 'warns and returns nothing when the API returns no fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Status = 200; Headers = @{}; Body = [pscustomobject]@{ fields = @() } } }
            $rows = Get-ImperionAutotaskOpportunityField
            $rows | Should -BeNullOrEmpty
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }
}
