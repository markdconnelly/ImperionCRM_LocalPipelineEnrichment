#Requires -Modules Pester
# Hermetic tests for Set-ImperionDefenderToBronze: multi-table router over the defender_*
# bronze set (front-end migration 0076). DB + upsert + log mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionDefenderToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            $script:upserts = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-ImperionBronzeUpsert {
                $script:upserts.Add(@{ Table = $Table; Rows = $Rows })
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }
        }
    }

    It 'routes a mixed batch by entity, projecting each table''s exact 0076 column set (entity stripped)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $rows = @(
                [pscustomobject]@{
                    entity = 'incidents'; display_name = 'Multi-stage incident'; severity = 'high'; status = 'active'
                    incident_web_url = 'https://security.microsoft.com/incidents/4321'; future_extra = 'dropme'
                    tenant_id = 't1'; source = 'defender'; external_id = '4321'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
                [pscustomobject]@{
                    entity = 'alerts'; incident_external_id = '4321'; title = 'Suspicious PowerShell'; severity = 'high'
                    mitre_techniques = 'T1059.001'; service_source = 'microsoftDefenderForEndpoint'
                    tenant_id = 't1'; source = 'defender'; external_id = 'a1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h2'
                }
            )
            $tally = $rows | Set-ImperionDefenderToBronze

            $tally.scanned | Should -Be 2
            ($script:upserts.Table | Sort-Object) | Should -Be @('defender_alerts', 'defender_incidents')

            $incidentUpsert = $script:upserts | Where-Object { $_.Table -eq 'defender_incidents' }
            ($incidentUpsert.Rows[0].PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'display_name', 'severity', 'status', 'classification', 'determination',
                    'assigned_to', 'redirect_incident_id', 'incident_web_url', 'custom_tags', 'system_tags',
                    'description', 'summary', 'resolving_comment', 'created_date_time', 'last_update_date_time',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)

            $alertUpsert = $script:upserts | Where-Object { $_.Table -eq 'defender_alerts' }
            $alertUpsert.Rows[0].incident_external_id | Should -Be '4321'   # the ADR-0059 layering key survives
            ($alertUpsert.Rows[0].PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'incident_external_id', 'provider_alert_id', 'title', 'severity', 'status',
                    'classification', 'determination', 'category', 'service_source', 'detection_source',
                    'detector_id', 'assigned_to', 'actor_display_name', 'threat_display_name',
                    'threat_family_name', 'mitre_techniques', 'alert_web_url', 'incident_web_url',
                    'description', 'recommended_actions', 'first_activity_date_time',
                    'last_activity_date_time', 'created_date_time', 'last_update_date_time',
                    'resolved_date_time',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
        }
    }

    It 'uses -Entity for rows without a discriminator' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $row = [pscustomobject]@{ title = 'A'; external_id = 'a2'; content_hash = 'h' }
            ($row | Set-ImperionDefenderToBronze -Entity alerts).scanned | Should -Be 1
            $script:upserts[0].Table | Should -Be 'defender_alerts'
        }
    }

    It 'fails loudly on an unknown entity (never invents a table) and never writes the ticket link' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $row = [pscustomobject]@{ entity = 'ticket_link'; external_id = 'x' }
            { $row | Set-ImperionDefenderToBronze } | Should -Throw "*unknown Defender entity 'ticket_link'*"
            { [pscustomobject]@{ external_id = 'x' } | Set-ImperionDefenderToBronze } | Should -Throw "*no 'entity' property*"
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            (@() | Set-ImperionDefenderToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ entity = 'incidents'; external_id = 'i1'; content_hash = 'h' }
            ($row | Set-ImperionDefenderToBronze -WhatIf).inserted | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
