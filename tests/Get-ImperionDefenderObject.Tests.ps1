#Requires -Modules Pester
# Hermetic tests for Get-ImperionDefenderObject: Graph token + requests mocked, routed by URI.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDefenderObject' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                switch -Regex ($Uri) {
                    'security/incidents' {
                        return @([pscustomobject]@{
                            id = '4321'; displayName = 'Multi-stage incident'; severity = 'high'; status = 'active'
                            classification = 'unknown'; determination = 'unknown'; assignedTo = 'soc@imperionllc.com'
                            incidentWebUrl = 'https://security.microsoft.com/incidents/4321'
                            customTags = @('vip', 'client-acme'); systemTags = @('Defender Experts')
                            createdDateTime = '2026-06-11T08:00:00Z'; lastUpdateDateTime = '2026-06-12T09:00:00Z'
                        })
                    }
                    'security/alerts_v2' {
                        return @([pscustomobject]@{
                            id = 'da637...123'; incidentId = '4321'; providerAlertId = 'p-1'
                            title = 'Suspicious PowerShell'; severity = 'high'; status = 'new'
                            category = 'Execution'; serviceSource = 'microsoftDefenderForEndpoint'
                            detectionSource = 'antivirus'; mitreTechniques = @('T1059.001', 'T1566')
                            alertWebUrl = 'https://security.microsoft.com/alerts/da637...123'
                            createdDateTime = '2026-06-11T08:01:00Z'
                        })
                    }
                    default { return @() }
                }
            }
        }
    }

    It 'collects incidents and alerts, stamped with entity + the standard envelope' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionDefenderObject)
            ($rows | Where-Object { $_.entity -eq 'incidents' }).Count | Should -Be 1
            ($rows | Where-Object { $_.entity -eq 'alerts' }).Count    | Should -Be 1

            $incident = $rows | Where-Object { $_.entity -eq 'incidents' }
            $incident.display_name | Should -Be 'Multi-stage incident'
            $incident.severity     | Should -Be 'high'
            $incident.custom_tags  | Should -Be 'vip; client-acme'
            $incident.source       | Should -Be 'defender'
            $incident.tenant_id    | Should -Be 'partner'
            $incident.external_id  | Should -Be '4321'
            $incident.content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'carries incident_external_id on alerts — the Autotask layering key (ADR-0059)' {
        InModuleScope ImperionPipeline {
            $alert = @(Get-ImperionDefenderObject) | Where-Object { $_.entity -eq 'alerts' }
            $alert.incident_external_id | Should -Be '4321'
            $alert.external_id          | Should -Be 'da637...123'
            $alert.mitre_techniques     | Should -Be 'T1059.001; T1566'
            $alert.service_source       | Should -Be 'microsoftDefenderForEndpoint'
        }
    }

    It 'does not throw when records omit optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match 'incidents') { return @([pscustomobject]@{ id = 'bare' }) }
                return @()
            }
            { Get-ImperionDefenderObject } | Should -Not -Throw
        }
    }

    It 'collects from the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionDefenderObject -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
