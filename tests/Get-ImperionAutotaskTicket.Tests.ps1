#Requires -Modules Pester
# Hermetic tests for Get-ImperionAutotaskTicket: context helper + request layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskTicket' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionAutotaskContext { [pscustomobject]@{ Headers = @{}; ApiBase = 'https://ws/V1.0' } }
        }
    }

    It 'flattens tickets to the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest {
                , @([pscustomobject]@{ id = 900; ticketNumber = 'T20260601.0001'; title = 'Server down'; status = 1; companyID = 101; lastActivityDate = '2026-06-01T00:00:00Z' })
            }
            $rows = Get-ImperionAutotaskTicket
            $rows[0].ticket_number | Should -Be 'T20260601.0001'
            $rows[0].title         | Should -Be 'Server down'
            $rows[0].company_id    | Should -Be '101'
            $rows[0].source        | Should -Be 'autotask'
            $rows[0].external_id   | Should -Be '900'
        }
    }

    It 'does not throw when a ticket omits optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @([pscustomobject]@{ id = 901; title = 'Bare' }) }
            { Get-ImperionAutotaskTicket } | Should -Not -Throw
        }
    }

    It 'queries Tickets incrementally on lastActivityDate when -SinceDays is given' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @() }
            Get-ImperionAutotaskTicket -SinceDays 1 | Out-Null
            Should -Invoke Invoke-ImperionAutotaskRequest -Times 1 -ParameterFilter { $Entity -eq 'Tickets' -and $Filter.field -eq 'lastActivityDate' }
        }
    }
}
