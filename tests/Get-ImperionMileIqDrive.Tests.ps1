#Requires -Modules Pester
# Hermetic tests for Get-ImperionMileIqDrive: DB mapping, per-employee token, connect layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMileIqDrive' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            # The collector reads employee_profile through Invoke-ImperionDbQuery; a fake
            # connection with a Dispose() keeps the own-connection path StrictMode-safe.
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
        }
    }

    It 'projects a business drive to the typed mileiq_drive shape with native CLR types and resolved app_user_id' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { , @([pscustomobject]@{ mileiq_user_id = 'mq-1'; app_user_id = 'user-7' }) }
            Mock Resolve-ImperionMileIqAccessToken { 'tok-mq-1' }
            Mock Invoke-ImperionMileIqRequest {
                , @([pscustomobject]@{
                        id              = 'DRV-100'
                        driveDate       = '2026-06-03'
                        miles           = 12.4
                        startLocation   = [pscustomobject]@{ name = 'Office' }
                        endLocation     = [pscustomobject]@{ name = 'Client Site' }
                        suggestedRate   = 0.67
                        suggestedAmount = 8.31
                        classification  = 'business'
                    })
            }
            $rows = @(Get-ImperionMileIqDrive)
            $rows.Count                | Should -Be 1
            $rows[0].mileiq_drive_id   | Should -Be 'DRV-100'
            $rows[0].mileiq_user_id    | Should -Be 'mq-1'
            $rows[0].app_user_id       | Should -Be 'user-7'
            $rows[0].drive_date        | Should -BeOfType ([DateOnly])
            $rows[0].miles             | Should -BeOfType ([decimal])
            $rows[0].miles             | Should -Be ([decimal]12.4)
            $rows[0].origin            | Should -Be 'Office'
            $rows[0].destination       | Should -Be 'Client Site'
            $rows[0].suggested_rate    | Should -Be ([decimal]0.67)
            $rows[0].suggested_amount  | Should -Be ([decimal]8.31)
            ($rows[0].payload_bronze | ConvertFrom-Json).id | Should -Be 'DRV-100'
        }
    }

    It 'leaves app_user_id null when the mapping has no app_user_id (merge resolves later) and stamps last_seen_at' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { , @([pscustomobject]@{ mileiq_user_id = 'mq-2'; app_user_id = $null }) }
            Mock Resolve-ImperionMileIqAccessToken { 'tok-mq-2' }
            Mock Invoke-ImperionMileIqRequest { , @([pscustomobject]@{ id = 'DRV-2'; miles = 3 }) }
            $row = (Get-ImperionMileIqDrive)[0]
            $row.app_user_id  | Should -BeNullOrEmpty
            $row.last_seen_at | Should -BeOfType ([datetimeoffset])
        }
    }

    It 'requests business-classified drives only (personal drives never enter)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { , @([pscustomobject]@{ mileiq_user_id = 'mq-1'; app_user_id = 'u1' }) }
            Mock Resolve-ImperionMileIqAccessToken { 'tok' }
            Mock Invoke-ImperionMileIqRequest { , @() }
            Get-ImperionMileIqDrive | Out-Null
            Should -Invoke Invoke-ImperionMileIqRequest -Times 1 -ParameterFilter {
                $Uri -match 'classification=business'
            }
        }
    }

    It 'skips an employee whose token resolves null and never calls the API (dormant-per-employee, fail closed)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { , @([pscustomobject]@{ mileiq_user_id = 'mq-x'; app_user_id = $null }) }
            Mock Resolve-ImperionMileIqAccessToken { $null }
            Mock Invoke-ImperionMileIqRequest { , @() }
            $rows = @(Get-ImperionMileIqDrive)
            $rows.Count | Should -Be 0
            Should -Invoke Invoke-ImperionMileIqRequest -Times 0
        }
    }

    It 'returns nothing without calling the API when no employee has a mileiq_user_id (dormant)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Resolve-ImperionMileIqAccessToken { 'tok' }
            Mock Invoke-ImperionMileIqRequest { , @() }
            $rows = @(Get-ImperionMileIqDrive)
            $rows.Count | Should -Be 0
            Should -Invoke Invoke-ImperionMileIqRequest -Times 0
            Should -Invoke Resolve-ImperionMileIqAccessToken -Times 0
        }
    }

    It 'pulls drives for every connected employee, tagging each row with its own user id' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{ mileiq_user_id = 'mq-a'; app_user_id = 'ua' },
                    [pscustomobject]@{ mileiq_user_id = 'mq-b'; app_user_id = 'ub' }
                )
            }
            Mock Resolve-ImperionMileIqAccessToken { "tok-$MileIqUserId" }
            Mock Invoke-ImperionMileIqRequest { , @([pscustomobject]@{ id = "DRV-$AccessToken"; miles = 1 }) }
            $rows = @(Get-ImperionMileIqDrive)
            $rows.Count | Should -Be 2
            ($rows.mileiq_user_id | Sort-Object) | Should -Be @('mq-a', 'mq-b')
        }
    }

    It 'passes a startDate filter when -SinceDays is given' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { , @([pscustomobject]@{ mileiq_user_id = 'mq-1'; app_user_id = 'u1' }) }
            Mock Resolve-ImperionMileIqAccessToken { 'tok' }
            Mock Invoke-ImperionMileIqRequest { , @() }
            Get-ImperionMileIqDrive -SinceDays 7 | Out-Null
            Should -Invoke Invoke-ImperionMileIqRequest -Times 1 -ParameterFilter { $Uri -match 'startDate=' }
        }
    }

    It 'omits the startDate filter for a full backfill (no -SinceDays)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { , @([pscustomobject]@{ mileiq_user_id = 'mq-1'; app_user_id = 'u1' }) }
            Mock Resolve-ImperionMileIqAccessToken { 'tok' }
            Mock Invoke-ImperionMileIqRequest { , @() }
            Get-ImperionMileIqDrive | Out-Null
            Should -Invoke Invoke-ImperionMileIqRequest -Times 1 -ParameterFilter { $Uri -notmatch 'startDate=' }
        }
    }
}
