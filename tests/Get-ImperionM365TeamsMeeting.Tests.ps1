#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365TeamsMeeting: Graph mocked. Per ADR-0126 / #380 the collector
# pulls EVERY online meeting from the user's calendar (no collection-time client filter; client
# scoping moved to silver, FE #1369).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        function script:New-Event {
            param($Id, $Subject, $Organizer, [string[]]$Attendees)
            [pscustomobject]@{
                id                    = $Id
                subject               = $Subject
                organizer             = [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $Organizer; name = $Organizer } }
                attendees             = @($Attendees | ForEach-Object { [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $_ } } })
                start                 = [pscustomobject]@{ dateTime = '2026-06-04T15:00:00'; timeZone = 'UTC' }
                end                   = [pscustomobject]@{ dateTime = '2026-06-04T15:30:00'; timeZone = 'UTC' }
                isOnlineMeeting       = $true
                onlineMeetingProvider = 'teamsForBusiness'
                onlineMeeting         = [pscustomobject]@{ joinUrl = "https://teams.microsoft.com/l/meetup/$Id" }
            }
        }
    }
}

Describe 'Get-ImperionM365TeamsMeeting' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
        }
    }

    It 'captures EVERY online meeting from the user calendar and flattens them (no collection-time client filter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @(
                    (New-Event -Id 'e1' -Subject 'Acme review' -Organizer 'ada@imperionllc.com' -Attendees @('sam@acme.com')),
                    (New-Event -Id 'e2' -Subject 'Internal sync' -Organizer 'ada@imperionllc.com' -Attendees @('bob@imperionllc.com'))
                )
            }

            $rows = @(Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com')
            # ADR-0126: both meetings land at bronze; the client filter is a silver concern (FE #1369).
            $rows.Count                 | Should -Be 2
            ($rows.external_id | Sort-Object) | Should -Be @('e1', 'e2')
            $clientRow = $rows | Where-Object { $_.external_id -eq 'e1' }
            $clientRow.subject          | Should -Be 'Acme review'
            $clientRow.organizer_address | Should -Be 'ada@imperionllc.com'
            $clientRow.attendee_addresses | Should -Match 'sam@acme.com'
            $clientRow.start_date_time   | Should -Match '2026-06-04'
            $clientRow.source            | Should -Be 'm365_teams'
        }
    }

    It 'does not throw on a meeting with no attendees and still captures it' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'x'; subject = 'Solo'; isOnlineMeeting = $true }) }
            { Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com' } | Should -Not -Throw
            @(Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com').Count | Should -Be 1
        }
    }
}
