#Requires -Modules Pester
# Hermetic tests for Get-ImperionScopedInteractionTeams: allowlist/client-set/Graph mocked; the real
# scope predicate runs end-to-end. Graph is called twice per in-scope chat (list chats, then messages).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        function script:New-Chat {
            param($Id, [string[]]$MemberEmails)
            [pscustomobject]@{
                id      = $Id
                chatType = 'oneOnOne'
                members = @($MemberEmails | ForEach-Object { [pscustomobject]@{ email = $_; displayName = $_ } })
            }
        }
        function script:New-ChatMsg {
            param($Id, $FromAddr, $Body)
            [pscustomobject]@{
                id              = $Id
                messageType     = 'message'
                createdDateTime = '2026-06-05T10:00:00Z'
                from            = [pscustomobject]@{ user = [pscustomobject]@{ email = $FromAddr; displayName = $FromAddr } }
                body            = [pscustomobject]@{ content = $Body; contentType = 'text' }
            }
        }
        function script:New-ClientSet {
            param([string[]]$Emails = @(), [string[]]$Domains = @())
            $e = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $d = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($x in $Emails) { [void]$e.Add($x) }
            foreach ($x in $Domains) { [void]$d.Add($x) }
            [pscustomobject]@{ Emails = $e; Domains = $d }
        }
    }
}

Describe 'Get-ImperionScopedInteractionTeams' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog { }
            Mock Resolve-ImperionClientContactSet { New-ClientSet -Domains @('acme.com') }
        }
    }

    It 'pulls messages ONLY from in-scope chats and flattens to m365_teams columns' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionInteractionAllowlist { , @('derek@imperionllc.com') }
            # First Graph call = the chats list; subsequent calls = messages for an in-scope chat.
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match '/chats\?\$expand=members$') {
                    , @(
                        (New-Chat -Id 'chat-client'   -MemberEmails @('derek@imperionllc.com', 'sam@acme.com')),
                        (New-Chat -Id 'chat-internal' -MemberEmails @('derek@imperionllc.com', 'mark@imperionllc.com'))
                    )
                }
                elseif ($Uri -match '/chats/chat-client/messages$') {
                    , @(
                        (New-ChatMsg -Id 'msg1' -FromAddr 'derek@imperionllc.com' -Body 'hi client'),
                        (New-ChatMsg -Id 'msg2' -FromAddr 'sam@acme.com' -Body 'reply')
                    )
                }
                else { , @() }
            }
            $rows = @(Get-ImperionScopedInteractionTeams -Connection ([pscustomobject]@{}))
            $rows.Count | Should -Be 2
            ($rows | Where-Object { $_.external_id -eq 'msg1' }).direction | Should -Be 'outbound'
            ($rows | Where-Object { $_.external_id -eq 'msg2' }).direction | Should -Be 'inbound'
            $rows[0].source          | Should -Be 'm365_teams'
            $rows[0].conversation_id | Should -Be 'chat-client'
            $rows[0].participants    | Should -Match 'sam@acme.com'
            $rows[0].captured_user   | Should -Be 'derek@imperionllc.com'
            # The internal chat's messages are never fetched.
            Should -Invoke Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match '/chats/chat-internal/messages' } -Times 0
        }
    }

    It 'is dormant (logs + returns nothing, no Graph call) when no allowlist is configured' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionInteractionAllowlist { $null }
            Mock Invoke-ImperionGraphRequest { , @() }
            @(Get-ImperionScopedInteractionTeams -Connection ([pscustomobject]@{})).Count | Should -Be 0
            Should -Invoke Invoke-ImperionGraphRequest -Times 0
        }
    }

    It 'does not throw on a chat with no members' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionInteractionAllowlist { , @('derek@imperionllc.com') }
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match 'expand=members$') { , @([pscustomobject]@{ id = 'empty'; members = @() }) } else { , @() }
            }
            { Get-ImperionScopedInteractionTeams -Connection ([pscustomobject]@{}) } | Should -Not -Throw
            @(Get-ImperionScopedInteractionTeams -Connection ([pscustomobject]@{})).Count | Should -Be 0
        }
    }
}
