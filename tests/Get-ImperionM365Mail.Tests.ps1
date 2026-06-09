#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365Mail: Graph token + request mocked; the cross-org filter is real.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    # Define the message builder in MODULE scope so the mocked Invoke-ImperionGraphRequest (which
    # runs in module scope under InModuleScope) can call it.
    InModuleScope ImperionPipeline {
        function script:New-Msg {
            param($Id, $Subject, $FromAddr, [string[]]$To, [string[]]$Cc = @())
            [pscustomobject]@{
                id               = $Id
                subject          = $Subject
                from             = [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $FromAddr; name = $FromAddr } }
                toRecipients     = @($To | ForEach-Object { [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $_ } } })
                ccRecipients     = @($Cc | ForEach-Object { [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $_ } } })
                receivedDateTime = '2026-06-05T10:00:00Z'
                conversationId   = "conv-$Id"
            }
        }
    }
}

Describe 'Get-ImperionM365Mail' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
        }
    }

    It 'keeps only the mail the cross-org filter accepts, and flattens it' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @(
                    (New-Msg -Id 'm1' -Subject 'Client thread' -FromAddr 'ada@imperionllc.com' -To @('sam@acme.com')),
                    (New-Msg -Id 'm2' -Subject 'Internal' -FromAddr 'ada@imperionllc.com' -To @('bob@imperionllc.com'))
                )
            }
            # The filter's own correctness is covered by Test-ImperionCrossOrgComm.Tests.ps1; here
            # we isolate the collector: accept only threads that include an acme.com participant.
            Mock Test-ImperionCrossOrgComm { [bool](@($Participant) -match 'acme\.com') }

            $rows = @(Get-ImperionM365Mail -Mailbox 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain @('acme.com'))
            $rows.Count           | Should -Be 1
            $rows[0].external_id  | Should -Be 'm1'
            $rows[0].subject      | Should -Be 'Client thread'
            $rows[0].from_address | Should -Be 'ada@imperionllc.com'
            $rows[0].to_addresses | Should -Be 'sam@acme.com'
            $rows[0].mailbox      | Should -Be 'ada@imperionllc.com'
            $rows[0].source       | Should -Be 'm365_email'
        }
    }

    It 'keeps client-tenant mail involving @imperionllc.com (ClientTenant mode)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @(
                    (New-Msg -Id 'c1' -Subject 'To MSP'      -FromAddr 'sam@acme.com' -To @('ada@imperionllc.com')),
                    (New-Msg -Id 'c2' -Subject 'Acme internal' -FromAddr 'sam@acme.com' -To @('joe@acme.com'))
                )
            }
            $rows = Get-ImperionM365Mail -Mailbox 'sam@acme.com' -Mode ClientTenant -TenantId 'customer-1'
            $rows.Count          | Should -Be 1
            $rows[0].external_id | Should -Be 'c1'
            Should -Invoke Get-ImperionGraphToken -ParameterFilter { $TenantId -eq 'customer-1' }
        }
    }

    It 'does not throw on a message missing cc/from and returns nothing when no mail qualifies' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'x'; subject = 'No recipients'; receivedDateTime = '2026-06-05T10:00:00Z' }) }
            { Get-ImperionM365Mail -Mailbox 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain 'acme.com' } | Should -Not -Throw
            @(Get-ImperionM365Mail -Mailbox 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain 'acme.com').Count | Should -Be 0
        }
    }
}
