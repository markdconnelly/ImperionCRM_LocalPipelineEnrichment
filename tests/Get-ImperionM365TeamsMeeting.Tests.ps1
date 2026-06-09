#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365TeamsMeeting: Graph mocked; filter mocked for the
# collector-isolation test (Test-ImperionCrossOrgComm has its own tests).

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
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
        }
    }

    It 'keeps only the meetings the cross-org filter accepts and flattens them' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @(
                    (New-Event -Id 'e1' -Subject 'Acme review' -Organizer 'ada@imperionllc.com' -Attendees @('sam@acme.com')),
                    (New-Event -Id 'e2' -Subject 'Internal sync' -Organizer 'ada@imperionllc.com' -Attendees @('bob@imperionllc.com'))
                )
            }
            Mock Test-ImperionCrossOrgComm { [bool](@($Participant) -match 'acme\.com') }

            $rows = @(Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain @('acme.com'))
            $rows.Count             | Should -Be 1
            $rows[0].external_id    | Should -Be 'e1'
            $rows[0].subject        | Should -Be 'Acme review'
            $rows[0].organizer_address | Should -Be 'ada@imperionllc.com'
            $rows[0].attendee_addresses | Should -Match 'sam@acme.com'
            $rows[0].start_date_time | Should -Match '2026-06-04'
            $rows[0].source         | Should -Be 'm365_teams'
        }
    }

    It 'keeps a client-tenant meeting that includes @imperionllc.com (real filter, ClientTenant)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @(
                    (New-Event -Id 'm1' -Subject 'With MSP' -Organizer 'sam@acme.com' -Attendees @('ada@imperionllc.com')),
                    (New-Event -Id 'm2' -Subject 'Acme only' -Organizer 'sam@acme.com' -Attendees @('joe@acme.com'))
                )
            }
            $rows = @(Get-ImperionM365TeamsMeeting -User 'sam@acme.com' -Mode ClientTenant -TenantId 'customer-1')
            $rows.Count          | Should -Be 1
            $rows[0].external_id | Should -Be 'm1'
        }
    }

    It 'does not throw on a meeting with no attendees' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'x'; subject = 'Solo' }) }
            { Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com' -Mode ClientTenant } | Should -Not -Throw
        }
    }
}
