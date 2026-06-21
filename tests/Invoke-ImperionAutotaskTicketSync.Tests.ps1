#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionAutotaskTicketSync: get + post layers mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionAutotaskTicketSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionAutotaskTicket { , @([pscustomobject]@{ external_id = '1' }) }
            Mock Set-ImperionAutotaskTicketToBronze { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Write-ImperionLog {}
        }
        Remove-Item Env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS -ErrorAction SilentlyContinue
    }
    AfterEach {
        Remove-Item Env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS -ErrorAction SilentlyContinue
    }

    It 'pipes the collector into the bronze writer and returns the tally' {
        InModuleScope ImperionPipeline {
            $tally = Invoke-ImperionAutotaskTicketSync
            $tally.inserted | Should -Be 1
            Should -Invoke Get-ImperionAutotaskTicket -Times 1
            Should -Invoke Set-ImperionAutotaskTicketToBronze -Times 1
        }
    }

    It 'defaults the window to 1 day when neither parameter nor env var is set' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionAutotaskTicketSync | Out-Null
            Should -Invoke Get-ImperionAutotaskTicket -Times 1 -ParameterFilter { $SinceDays -eq 1 }
        }
    }

    It 'honors IMPERION_AUTOTASK_TICKET_SINCE_DAYS when no parameter is given' {
        $env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS = '14'
        InModuleScope ImperionPipeline {
            Invoke-ImperionAutotaskTicketSync | Out-Null
            Should -Invoke Get-ImperionAutotaskTicket -Times 1 -ParameterFilter { $SinceDays -eq 14 }
        }
    }

    It 'lets an explicit -SinceDays 0 request a full backfill (overriding the env var)' {
        $env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS = '14'
        InModuleScope ImperionPipeline {
            Invoke-ImperionAutotaskTicketSync -SinceDays 0 | Out-Null
            Should -Invoke Get-ImperionAutotaskTicket -Times 1 -ParameterFilter { $SinceDays -eq 0 }
        }
    }
}
