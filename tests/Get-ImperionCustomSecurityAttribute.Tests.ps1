#Requires -Modules Pester
# Hermetic tests for Get-ImperionCustomSecurityAttribute: Graph token + request mocked (issue #141).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionCustomSecurityAttribute' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'Engineering_Project'; attributeSet = 'Engineering'; name = 'Project'
                        description = 'Project code'; type = 'String'; status = 'Available'
                        isCollection = $true; isSearchable = $true; usePreDefinedValuesOnly = $true
                        allowedValues = @(
                            [pscustomobject]@{ id = 'Alpha'; isActive = $true }
                            [pscustomobject]@{ id = 'Beta'; isActive = $true }
                        )
                    }
                    [pscustomobject]@{
                        id = 'HR_Clearance'; attributeSet = 'HR'; name = 'Clearance'
                        type = 'String'; status = 'Available'; isCollection = $false
                        usePreDefinedValuesOnly = $false; allowedValues = @()
                    }
                )
            }
        }
    }

    It 'flattens definitions to the schema-259 columns + standard envelope (id = set_name)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionCustomSecurityAttribute)
            $rows.Count | Should -Be 2

            $proj = $rows | Where-Object { $_.external_id -eq 'Engineering_Project' }
            $proj.attribute_set  | Should -Be 'Engineering'
            $proj.attribute_name | Should -Be 'Project'
            $proj.type           | Should -Be 'String'
            $proj.status         | Should -Be 'Available'
            $proj.is_collection  | Should -Be 'true'
            $proj.use_predefined_values_only | Should -Be 'true'
            $proj.allowed_values | Should -Be 'Alpha; Beta'
            $proj.source         | Should -Be 'm365'
            $proj.tenant_id      | Should -Be 'partner'
            $proj.content_hash   | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'leaves allowed_values empty when there is no predefined list' {
        InModuleScope ImperionPipeline {
            $hr = @(Get-ImperionCustomSecurityAttribute) | Where-Object { $_.external_id -eq 'HR_Clearance' }
            $hr.allowed_values | Should -BeNullOrEmpty
        }
    }

    It 'requests definitions with $expand=allowedValues' {
        InModuleScope ImperionPipeline {
            Get-ImperionCustomSecurityAttribute | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/directory/customSecurityAttributeDefinitions?$expand=allowedValues'
            }
        }
    }

    It 'does not throw when a definition omits optional fields (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { @([pscustomobject]@{ id = 'S_A'; attributeSet = 'S'; name = 'A' }) }
            { Get-ImperionCustomSecurityAttribute } | Should -Not -Throw
            (@(Get-ImperionCustomSecurityAttribute)[0]).allowed_values | Should -BeNullOrEmpty
        }
    }

    It 'collects from the requested tenant (GDAP)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionCustomSecurityAttribute -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
