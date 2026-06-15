#Requires -Modules Pester
# Hermetic tests for Get-ImperionIntuneManagedApp: Graph token + request mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionIntuneManagedApp' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens managed apps to the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @([pscustomobject]@{
                        id = 'app-1'; '@odata.type' = '#microsoft.graph.win32LobApp'
                        displayName = '7-Zip'; publisher = 'Igor Pavlov'; publishingState = 'published'
                        isFeatured = $true; isAssigned = $true; version = '23.01'
                    })
            }
            $rows = Get-ImperionIntuneManagedApp
            $rows[0].display_name     | Should -Be '7-Zip'
            $rows[0].app_type         | Should -Be 'win32LobApp'   # @odata.type namespace trimmed
            $rows[0].publisher        | Should -Be 'Igor Pavlov'
            $rows[0].publishing_state | Should -Be 'published'
            $rows[0].is_featured      | Should -Be 'true'          # bool coerced to text
            $rows[0].version          | Should -Be '23.01'
            $rows[0].source           | Should -Be 'm365'
            $rows[0].external_id      | Should -Be 'app-1'
        }
    }

    It 'leaves app_type null when @odata.type is absent and does not throw on sparse apps' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'app-2'; displayName = 'Bare App' }) }
            { Get-ImperionIntuneManagedApp } | Should -Not -Throw
            $rows = @(Get-ImperionIntuneManagedApp)
            $rows[0].display_name | Should -Be 'Bare App'
            $rows[0].app_type     | Should -BeNullOrEmpty
        }
    }

    It 'collects from the requested tenant via GDAP token' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionIntuneManagedApp -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
