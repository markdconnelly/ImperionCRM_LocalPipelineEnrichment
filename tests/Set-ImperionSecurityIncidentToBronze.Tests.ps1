#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionSecurityIncidentToBronze (multi-table router over
# Invoke-ImperionBronzePost). No DB; the upsert + logging are mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionSecurityIncidentToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
        }
    }

    It 'routes incident / alert / evidence rows to their m365_* tables by the entity discriminator' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured[$Table] = $Rows; [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 } }

            $incident = [pscustomobject]@{ entity = 'incidents'; incident_id = 'inc-1'; title = 'I'; severity = 'high'; status = 'active'; classification = 'tp'; autotask_ticket_ref = 'T123'; assigned_to = 'soc'; created_at = 'c'; last_update_at = 'u'; tenant_id = 't'; source = 'm365'; external_id = 'inc-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h1'; strayField = 'drop' }
            $alert    = [pscustomobject]@{ entity = 'alerts'; alert_id = 'a-1'; incident_id = 'inc-1'; title = 'A'; severity = 'high'; category = 'Exec'; mitre_techniques = 'T1059'; detection_source = 'av'; created_at = 'c'; tenant_id = 't'; source = 'm365'; external_id = 'a-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h2' }
            $evidence = [pscustomobject]@{ entity = 'evidence'; evidence_id = 'a-1::0'; alert_id = 'a-1'; evidence_type = 'device'; entity_value = 'WS-01'; verdict = 'malicious'; remediation_status = 'remediated'; tenant_id = 't'; source = 'm365'; external_id = 'a-1::0'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h3' }

            $tally = @($incident, $alert, $evidence) | Set-ImperionSecurityIncidentToBronze -Confirm:$false
            $tally.inserted | Should -Be 3

            $captured.Keys | Should -Contain 'm365_incidents'
            $captured.Keys | Should -Contain 'm365_alerts'
            $captured.Keys | Should -Contain 'm365_evidence'

            # autotask_ticket_ref survives the incident projection; the FK columns survive on children.
            $captured['m365_incidents'][0].autotask_ticket_ref | Should -Be 'T123'
            $captured['m365_incidents'][0].PSObject.Properties.Name | Should -Not -Contain 'strayField'
            $captured['m365_incidents'][0].PSObject.Properties.Name | Should -Not -Contain 'entity'
            $captured['m365_alerts'][0].incident_id | Should -Be 'inc-1'
            $captured['m365_evidence'][0].alert_id  | Should -Be 'a-1'
        }
    }

    It 'fails loudly on an unknown entity (never invents a table)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $bad = [pscustomobject]@{ entity = 'unicorns'; external_id = 'x' }
            { $bad | Set-ImperionSecurityIncidentToBronze -Confirm:$false } | Should -Throw '*unknown security entity*'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionSecurityIncidentToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ entity = 'incidents'; incident_id = 'inc-1'; tenant_id = 't'; source = 'm365'; external_id = 'inc-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $row | Set-ImperionSecurityIncidentToBronze -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
