#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365Device: Graph token + request mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionM365Device' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
        }
    }

    It 'flattens managed devices to the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @([pscustomobject]@{ id = 'd1'; deviceName = 'LAPTOP-01'; operatingSystem = 'Windows'; osVersion = '10.0.22631'; complianceState = 'compliant'; serialNumber = 'SN123'; userPrincipalName = 'ada@imperionllc.com' })
            }
            $rows = Get-ImperionM365Device
            $rows[0].device_name      | Should -Be 'LAPTOP-01'
            $rows[0].os               | Should -Be 'Windows'
            $rows[0].compliance_state | Should -Be 'compliant'
            $rows[0].serial_number    | Should -Be 'SN123'
            $rows[0].source           | Should -Be 'm365'
            $rows[0].external_id      | Should -Be 'd1'
        }
    }

    It 'does not throw when a device omits optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'd2'; deviceName = 'Bare' }) }
            { Get-ImperionM365Device } | Should -Not -Throw
        }
    }

    It 'collects from the requested tenant via GDAP token' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionM365Device -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
