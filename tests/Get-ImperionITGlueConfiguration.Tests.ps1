#Requires -Modules Pester
# Hermetic tests for Get-ImperionITGlueConfiguration: secrets + IT Glue request mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionITGlueConfiguration' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner'; ITGlue = @{ BaseUri = 'https://api.itglue.com' } } }
            Mock Resolve-ImperionITGlueApiKey { 'key-value' }
        }
    }

    It 'flattens configuration (device) attributes to the bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest {
                , @([pscustomobject]@{ id = '500'; type = 'configurations'; attributes = [pscustomobject]@{
                            name = 'SRV-01'; hostname = 'srv-01'; 'configuration-type-name' = 'Server'; 'operating-system-name' = 'Windows Server 2022'
                            'serial-number' = 'SN-500'; 'manufacturer-name' = 'Dell'; 'organization-id' = 42
                        } })
            }
            $rows = Get-ImperionITGlueConfiguration
            $rows[0].name             | Should -Be 'SRV-01'
            $rows[0].configuration_type | Should -Be 'Server'
            $rows[0].operating_system | Should -Be 'Windows Server 2022'
            $rows[0].serial_number    | Should -Be 'SN-500'
            $rows[0].organization_id  | Should -Be '42'
            $rows[0].source           | Should -Be 'itglue'
            $rows[0].external_id      | Should -Be '500'
        }
    }

    It 'does not throw when a configuration omits optional attributes' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest { , @([pscustomobject]@{ id = '501'; type = 'configurations'; attributes = [pscustomobject]@{ name = 'Bare' } }) }
            { Get-ImperionITGlueConfiguration } | Should -Not -Throw
            (Get-ImperionITGlueConfiguration)[0].serial_number | Should -BeNullOrEmpty
        }
    }

    It 'requests the configurations endpoint' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest { , @() }
            Get-ImperionITGlueConfiguration | Out-Null
            Should -Invoke Invoke-ImperionITGlueRequest -Times 1 -ParameterFilter { $Path -eq 'configurations' }
        }
    }
}
