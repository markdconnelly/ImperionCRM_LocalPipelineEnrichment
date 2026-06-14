#Requires -Modules Pester
# Hermetic tests for Get-ImperionAutotaskTimeEntry: context helper + request layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskTimeEntry' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionAutotaskContext { [pscustomobject]@{ Headers = @{}; ApiBase = 'https://ws/V1.0' } }
        }
    }

    It 'projects a TimeEntry to the typed autotask_time_entry column set with native CLR types' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest {
                , @([pscustomobject]@{
                        id            = 5500
                        resourceID    = 42
                        ticketID      = 900
                        dateWorked    = '2026-06-01T00:00:00'
                        startDateTime = '2026-06-01T09:00:00Z'
                        endDateTime   = '2026-06-01T11:30:00Z'
                        hoursWorked   = 2.5
                    })
            }
            $rows = Get-ImperionAutotaskTimeEntry
            $rows[0].external_ref         | Should -Be '5500'
            $rows[0].autotask_resource_id | Should -BeOfType ([long])
            $rows[0].autotask_resource_id | Should -Be 42
            $rows[0].autotask_ticket_id   | Should -Be 900
            $rows[0].work_date            | Should -BeOfType ([DateOnly])
            $rows[0].started_at           | Should -BeOfType ([datetimeoffset])
            $rows[0].hours_worked         | Should -BeOfType ([decimal])
            $rows[0].hours_worked         | Should -Be ([decimal]2.5)
            ($rows[0].payload_bronze | ConvertFrom-Json).id | Should -Be 5500
        }
    }

    It 'never emits app_user_id or matched_at (the merge owns resolution)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @([pscustomobject]@{ id = 1; resourceID = 7 }) }
            $names = (Get-ImperionAutotaskTimeEntry)[0].PSObject.Properties.Name
            $names | Should -Not -Contain 'app_user_id'
            $names | Should -Not -Contain 'matched_at'
        }
    }

    It 'leaves missing/unparseable typed fields null without throwing' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @([pscustomobject]@{ id = 2; hoursWorked = 'n/a' }) }
            { Get-ImperionAutotaskTimeEntry } | Should -Not -Throw
            $row = (Get-ImperionAutotaskTimeEntry)[0]
            $row.external_ref         | Should -Be '2'
            $row.autotask_resource_id | Should -BeNullOrEmpty
            $row.work_date            | Should -BeNullOrEmpty
            $row.hours_worked         | Should -BeNullOrEmpty
        }
    }

    It 'queries TimeEntries incrementally on lastModifiedDateTime when -SinceDays is given' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @() }
            Get-ImperionAutotaskTimeEntry -SinceDays 7 | Out-Null
            Should -Invoke Invoke-ImperionAutotaskRequest -Times 1 -ParameterFilter {
                $Entity -eq 'TimeEntries' -and $Filter.field -eq 'lastModifiedDateTime'
            }
        }
    }

    It 'pulls the full set (id gte 0) when -SinceDays is omitted' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionAutotaskRequest { , @() }
            Get-ImperionAutotaskTimeEntry | Out-Null
            Should -Invoke Invoke-ImperionAutotaskRequest -Times 1 -ParameterFilter {
                $Entity -eq 'TimeEntries' -and $Filter.field -eq 'id'
            }
        }
    }
}
