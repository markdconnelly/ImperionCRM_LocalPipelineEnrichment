#Requires -Modules Pester
# Hermetic tests for Get-ImperionScopedInteractionMail: allowlist/Graph mocked. Per ADR-0126 / #380
# the collector pulls EVERY home-tenant message from the allowlisted mailboxes (no collection-time
# client filter; client scoping moved to silver, FE #1369). The allowlist only selects mailboxes.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        function script:New-Msg {
            param($Id, $Subject, $FromAddr, [string[]]$To, [string[]]$Cc = @())
            [pscustomobject]@{
                id               = $Id
                subject          = $Subject
                bodyPreview      = "preview of $Id"
                from             = [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $FromAddr; name = $FromAddr } }
                toRecipients     = @($To | ForEach-Object { [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $_ } } })
                ccRecipients     = @($Cc | ForEach-Object { [pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $_ } } })
                receivedDateTime = '2026-06-05T10:00:00Z'
                sentDateTime     = '2026-06-05T09:59:00Z'
                conversationId   = "conv-$Id"
                hasAttachments   = $false
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

Describe 'Get-ImperionScopedInteractionMail' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog { }
        }
    }

    It 'pulls EVERY message from the allowlisted mailbox and flattens to m365_email columns (no collection-time client filter)' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionInteractionAllowlist { , @('derek@imperionllc.com') }
            Mock Invoke-ImperionGraphRequest {
                $client = New-Msg -Id 'm1' -Subject 'Client thread' -FromAddr 'derek@imperionllc.com' -To @('sam@acme.com')
                $internal = New-Msg -Id 'm2' -Subject 'Internal' -FromAddr 'derek@imperionllc.com' -To @('mark@imperionllc.com')
                $vendor = New-Msg -Id 'm3' -Subject 'Vendor' -FromAddr 'derek@imperionllc.com' -To @('rep@microsoft.com')
                , @($client, $internal, $vendor)
            }
            $rows = @(Get-ImperionScopedInteractionMail -Connection ([pscustomobject]@{}))
            # ADR-0126: all three land at bronze; the client filter is a silver concern (FE #1369).
            $rows.Count           | Should -Be 3
            ($rows.external_id | Sort-Object) | Should -Be @('m1', 'm2', 'm3')
            $clientRow = $rows | Where-Object { $_.external_id -eq 'm1' }
            $clientRow.message_id    | Should -Be 'm1'
            $clientRow.subject       | Should -Be 'Client thread'
            $clientRow.from_address  | Should -Be 'derek@imperionllc.com'
            $clientRow.to_recipients | Should -Be 'sam@acme.com'
            $clientRow.direction     | Should -Be 'outbound'
            $clientRow.mailbox_owner | Should -Be 'derek@imperionllc.com'
            $clientRow.source        | Should -Be 'm365_email'
        }
    }

    It 'marks inbound mail (client -> principal) correctly' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionInteractionAllowlist { , @('derek@imperionllc.com') }
            Mock Invoke-ImperionGraphRequest { , @((New-Msg -Id 'i1' -Subject 'From client' -FromAddr 'sam@acme.com' -To @('derek@imperionllc.com'))) }
            $rows = @(Get-ImperionScopedInteractionMail -Connection ([pscustomobject]@{}))
            $rows.Count        | Should -Be 1
            $rows[0].direction | Should -Be 'inbound'
        }
    }

    It 'is dormant (logs + returns nothing, no Graph call) when no allowlist is configured' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionInteractionAllowlist { $null }
            Mock Invoke-ImperionGraphRequest { , @() }
            @(Get-ImperionScopedInteractionMail -Connection ([pscustomobject]@{})).Count | Should -Be 0
            Should -Invoke Invoke-ImperionGraphRequest -Times 0
            Should -Invoke Write-ImperionLog -Times 1
        }
    }

    It 'does not throw on a message missing from/recipients and still captures it (inbound by default)' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionInteractionAllowlist { , @('derek@imperionllc.com') }
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'x'; subject = 'No recipients'; receivedDateTime = '2026-06-05T10:00:00Z' }) }
            { Get-ImperionScopedInteractionMail -Connection ([pscustomobject]@{}) } | Should -Not -Throw
            $rows = @(Get-ImperionScopedInteractionMail -Connection ([pscustomobject]@{}))
            $rows.Count          | Should -Be 1
            $rows[0].external_id | Should -Be 'x'
            $rows[0].direction   | Should -Be 'inbound'
        }
    }
}
