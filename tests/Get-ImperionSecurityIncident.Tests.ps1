#Requires -Modules Pester
# Hermetic tests for Get-ImperionSecurityIncident: Graph token + request mocked (incidents with
# expanded alerts + evidence). No live calls, no SecretStore.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionSecurityIncident' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                , @([pscustomobject]@{
                        id             = 'inc-1'
                        displayName    = 'Multi-stage incident'
                        severity       = 'high'
                        status         = 'active'
                        classification = 'truePositive'
                        assignedTo     = 'soc@imperionllc.com'
                        customTags     = @('AutotaskTicket:T20260615.0042', 'vip')
                        systemTags     = @('Defender Experts')
                        createdDateTime    = '2026-06-11T08:00:00Z'
                        lastUpdateDateTime = '2026-06-12T09:00:00Z'
                        alerts = @(
                            [pscustomobject]@{
                                id              = 'alert-1'
                                incidentId      = 'inc-1'
                                title           = 'Suspicious PowerShell'
                                severity        = 'high'
                                category        = 'Execution'
                                mitreTechniques = @('T1059.001', 'T1566')
                                detectionSource = 'antivirus'
                                createdDateTime = '2026-06-11T08:01:00Z'
                                evidence = @(
                                    [pscustomobject]@{
                                        '@odata.type'     = '#microsoft.graph.security.deviceEvidence'
                                        displayName       = 'WS-01'
                                        verdict           = 'malicious'
                                        remediationStatus = 'remediated'
                                    },
                                    [pscustomobject]@{
                                        '@odata.type'     = '#microsoft.graph.security.userEvidence'
                                        displayName       = 'jdoe@acme.com'
                                        verdict           = 'suspicious'
                                        remediationStatus = 'none'
                                    }
                                )
                            }
                        )
                    })
            }
        }
    }

    It 'collects incident, alert, and evidence rows with the entity discriminator + standard envelope' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionSecurityIncident)
            ($rows | Where-Object entity -eq 'incidents').Count | Should -Be 1
            ($rows | Where-Object entity -eq 'alerts').Count    | Should -Be 1
            ($rows | Where-Object entity -eq 'evidence').Count  | Should -Be 2

            $incident = $rows | Where-Object entity -eq 'incidents'
            $incident.incident_id    | Should -Be 'inc-1'
            $incident.title          | Should -Be 'Multi-stage incident'
            $incident.severity       | Should -Be 'high'
            $incident.source         | Should -Be 'm365'
            $incident.tenant_id      | Should -Be 'partner'
            $incident.external_id    | Should -Be 'inc-1'
            $incident.content_hash   | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'links alert -> incident (incident_id FK) and evidence -> alert (alert_id FK)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionSecurityIncident)
            $alert = $rows | Where-Object entity -eq 'alerts'
            $alert.alert_id         | Should -Be 'alert-1'
            $alert.incident_id      | Should -Be 'inc-1'
            $alert.mitre_techniques | Should -Be 'T1059.001; T1566'
            $alert.detection_source | Should -Be 'antivirus'

            $evidence = @($rows | Where-Object entity -eq 'evidence')
            $evidence[0].alert_id           | Should -Be 'alert-1'
            $evidence[0].evidence_type      | Should -Be '#microsoft.graph.security.deviceEvidence'
            $evidence[0].entity_value       | Should -Be 'WS-01'
            $evidence[0].verdict            | Should -Be 'malicious'
            $evidence[0].remediation_status | Should -Be 'remediated'
            # Synthesized stable external_id = alertId::ordinal so re-runs converge.
            $evidence[0].external_id        | Should -Be 'alert-1::0'
            $evidence[1].external_id        | Should -Be 'alert-1::1'
        }
    }

    It 'stores the autotask_ticket_ref RAW (passthrough, no transform) from the configured candidate' {
        InModuleScope ImperionPipeline {
            # Default candidate path is customTags; value is the joined raw tag set (untouched).
            $incident = @(Get-ImperionSecurityIncident) | Where-Object entity -eq 'incidents'
            $incident.autotask_ticket_ref | Should -Be 'AutotaskTicket:T20260615.0042; vip'
            # The full raw tag set is always preserved losslessly.
            $incident.raw_payload | Should -Match 'AutotaskTicket'
        }
    }

    It 'honours an overridden autotask_ticket_ref candidate path (confirm-before-live repoint)' {
        InModuleScope ImperionPipeline {
            $incident = @(Get-ImperionSecurityIncident -AutotaskRefCandidatePath @('systemTags')) | Where-Object entity -eq 'incidents'
            $incident.autotask_ticket_ref | Should -Be 'Defender Experts'
        }
    }

    It 'does not throw on a bare incident with no alerts or evidence' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @([pscustomobject]@{ id = 'bare' }) }
            { Get-ImperionSecurityIncident } | Should -Not -Throw
            $rows = @(Get-ImperionSecurityIncident)
            @($rows | Where-Object entity -eq 'incidents').Count | Should -Be 1
            @($rows | Where-Object entity -eq 'alerts').Count    | Should -Be 0
        }
    }

    It 'authenticates read-only Graph against the requested tenant (per-tenant isolation)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionSecurityIncident -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
