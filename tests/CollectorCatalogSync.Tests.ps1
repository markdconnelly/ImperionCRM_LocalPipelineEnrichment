#Requires -Modules Pester
# Catalog test for the collector-catalog promotion (epic #286): every loose .task.ps1 is now an
# exported *Sync cmdlet. Asserts each is exported as an advanced function, plus behavioral
# spot-checks that the thin orchestrators compose their get/post (or EstateSweep) layer.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Collector catalog *Sync cmdlets are exported (epic #286)' {
    $catalog = @(
        'Invoke-ImperionAutotaskTimeEntrySync'
        'Invoke-ImperionM365UserSync', 'Invoke-ImperionM365DeviceSync', 'Invoke-ImperionDefenderSync'
        'Invoke-ImperionIntuneAppSync', 'Invoke-ImperionIntuneDeviceSync', 'Invoke-ImperionEntraAuthMethodSync'
        'Invoke-ImperionCustomSecurityAttributeSync', 'Invoke-ImperionSensitivityLabelSync'
        'Invoke-ImperionSharePointSiteSync', 'Invoke-ImperionEntraAppRegistrationSync'
        'Invoke-ImperionEntraDomainSync', 'Invoke-ImperionEntraGroupMemberSync', 'Invoke-ImperionEntraGroupSync'
        'Invoke-ImperionEntraRoleAssignmentSync', 'Invoke-ImperionM365MailSync', 'Invoke-ImperionM365TeamsChatSync'
        'Invoke-ImperionM365TeamsMeetingSync', 'Invoke-ImperionScopedInteractionMailSync'
        'Invoke-ImperionScopedInteractionTeamsSync', 'Invoke-ImperionQboAccountSync', 'Invoke-ImperionQboBillSync'
        'Invoke-ImperionQboCustomerSync', 'Invoke-ImperionQboEstimateSync', 'Invoke-ImperionQboExpenseAccountSync'
        'Invoke-ImperionQboInvoiceSync', 'Invoke-ImperionQboPaymentSync', 'Invoke-ImperionQboProfitAndLossSync'
        'Invoke-ImperionQboPurchaseSync', 'Invoke-ImperionITGlueOrganizationSync', 'Invoke-ImperionITGlueContactSync'
        'Invoke-ImperionITGlueConfigurationSync', 'Invoke-ImperionDattoRmmDeviceSync', 'Invoke-ImperionDattoBcdrBackupSync'
        'Invoke-ImperionCdwOrderSync', 'Invoke-ImperionAmazonBusinessOrderSync', 'Invoke-ImperionTelivyReportSync'
        'Invoke-ImperionMileIqDriveSync', 'Invoke-ImperionMyItProcessRecommendationSync', 'Invoke-ImperionPlaudRecordingSync'
        'Invoke-ImperionDocuSignEnvelopeSync', 'Invoke-ImperionDarkWebIdCompromiseSync', 'Invoke-ImperionEasyDmarcDomainSync'
        'Invoke-ImperionAzureResourceInventorySync', 'Invoke-ImperionSentinelSync', 'Invoke-ImperionDnsZoneSync'
        'Invoke-ImperionDnsResolveSync', 'Invoke-ImperionKqmOpportunitySync', 'Invoke-ImperionSecurityIncidentSync'
        'Invoke-ImperionMetaSocialSync', 'Invoke-ImperionMetaInsightSync'
    )

    It '<_> is an exported advanced function' -ForEach $catalog {
        $cmd = Get-Command -Module ImperionPipeline -Name $_ -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.CommandType | Should -Be 'Function'
        $cmd.CmdletBinding | Should -BeTrue
    }
}

Describe 'Collector *Sync cmdlets compose their collection layer' {
    It 'M365 EstateSweep wrapper delegates to Invoke-ImperionM365EstateSweep' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionM365EstateSweep {}
            Invoke-ImperionM365UserSync
            Should -Invoke Invoke-ImperionM365EstateSweep -Times 1
        }
    }

    It 'a get|post wrapper pipes the collector into the bronze writer' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionQboInvoice { , @([pscustomobject]@{ external_id = '1' }) }
            Mock Set-ImperionQboInvoiceToBronze { [pscustomobject]@{ scanned = 1; inserted = 1 } }
            Invoke-ImperionQboInvoiceSync | Out-Null
            Should -Invoke Get-ImperionQboInvoice -Times 1
            Should -Invoke Set-ImperionQboInvoiceToBronze -Times 1
        }
    }

    It 'a gated wrapper logs + exits cleanly when its collector throws (fail-closed)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecurityIncident { throw 'no consent' }
            Mock Set-ImperionSecurityIncidentToBronze {}
            Mock Write-ImperionLog {}
            { Invoke-ImperionSecurityIncidentSync } | Should -Not -Throw
            Should -Invoke Write-ImperionLog -Times 1
        }
    }
}
