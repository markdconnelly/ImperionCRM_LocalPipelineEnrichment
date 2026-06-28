#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365TeamsChat: Graph token + request mocked; filter mocked for
# the collector-isolation test (Test-ImperionCrossOrgComm has its own tests).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        function script:New-Chat {
            param($Id, $Topic, [string[]]$Members)
            [pscustomobject]@{
                id                 = $Id
                topic              = $Topic
                chatType           = 'group'
                members            = @($Members | ForEach-Object { [pscustomobject]@{ email = $_; displayName = $_ } })
                createdDateTime    = '2026-06-01T00:00:00Z'
                lastUpdatedDateTime = '2026-06-05T00:00:00Z'
                webUrl             = "https://teams.microsoft.com/$Id"
            }
        }
    }
}

Describe 'Get-ImperionM365TeamsChat' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
        }
    }

    It 'keeps only the chats the cross-org filter accepts and flattens them' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @(
                    (New-Chat -Id 'c1' -Topic 'Acme rollout' -Members @('ada@imperionllc.com', 'sam@acme.com')),
                    (New-Chat -Id 'c2' -Topic 'Internal' -Members @('ada@imperionllc.com', 'bob@imperionllc.com'))
                )
            }
            Mock Test-ImperionCrossOrgComm { [bool](@($Participant) -match 'acme\.com') }

            $rows = @(Get-ImperionM365TeamsChat -User 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain @('acme.com'))
            $rows.Count          | Should -Be 1
            $rows[0].external_id | Should -Be 'c1'
            $rows[0].topic       | Should -Be 'Acme rollout'
            $rows[0].member_emails | Should -Match 'sam@acme.com'
            $rows[0].user        | Should -Be 'ada@imperionllc.com'
            $rows[0].source      | Should -Be 'm365_teams'
        }
    }

    It 'keeps a client-tenant chat that includes @imperionllc.com (real filter, ClientTenant)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                , @(
                    (New-Chat -Id 'k1' -Topic 'With MSP' -Members @('sam@acme.com', 'ada@imperionllc.com')),
                    (New-Chat -Id 'k2' -Topic 'Acme only' -Members @('sam@acme.com', 'joe@acme.com'))
                )
            }
            $rows = @(Get-ImperionM365TeamsChat -User 'sam@acme.com' -Mode ClientTenant -TenantId 'customer-1')
            $rows.Count          | Should -Be 1
            $rows[0].external_id | Should -Be 'k1'
        }
    }

    It 'does not throw on a chat with no members' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'x'; topic = 'Empty' }) }
            { Get-ImperionM365TeamsChat -User 'ada@imperionllc.com' -Mode ClientTenant } | Should -Not -Throw
        }
    }
}
