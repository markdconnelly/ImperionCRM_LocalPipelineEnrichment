#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionSoftwareCiMerge: ShouldProcess gating, the ON CONFLICT
# (source, device_id, external_ref) upsert idempotency contract, dropping apps whose device can't
# be resolved, and the regex-guarded bronze text collected_at -> last_seen_at (issue #354; the
# on-prem populate twin of front-end #652 / migration 0204, ADR-0026 merge-co-locates-with-ingestion).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionSoftwareCiMerge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
        }
    }

    It 'honors -WhatIf: no connection, no read, no write' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 0 }
            Invoke-ImperionSoftwareCiMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbQuery -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    It 'no bronze rows -> clean no-op (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 1 }
            $r = Invoke-ImperionSoftwareCiMerge -Confirm:$false
            $r.apps | Should -Be 0
            $r.merged | Should -Be 0
            $r.unresolved | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    Context 'merge contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                # Row 1: device resolved (real install) — Chrome. Row 2: device resolved with junk
                # collected_at — Teams. Row 3: device UNRESOLVED (no silver device yet) -> dropped.
                Mock Invoke-ImperionDbQuery {
                    @(
                        [pscustomobject]@{ external_ref = 'dev1|app1'; name = 'Google Chrome'; publisher = 'Google'; version = '120.0'; platform = 'windows'; install_state = 'installed'; tenant_id = 't1'; collected_at = '2026-06-18T00:00:00Z'; device_id = 'dev-uuid-1'; account_id = 'acc-1' }
                        [pscustomobject]@{ external_ref = 'dev1|app2'; name = 'Microsoft Teams'; publisher = 'Microsoft'; version = '1.6'; platform = 'windows'; install_state = 'failed'; tenant_id = 't1'; collected_at = 'junk'; device_id = 'dev-uuid-1'; account_id = 'acc-1' }
                        [pscustomobject]@{ external_ref = 'dev9|app3'; name = 'Slack'; publisher = 'Slack'; version = '4.0'; platform = 'macOS'; install_state = 'installed'; tenant_id = 't1'; collected_at = '2026-06-18T00:00:00Z'; device_id = $null; account_id = $null }
                    )
                }
                $script:capturedSql = $null
                $script:capturedParams = [System.Collections.Generic.List[hashtable]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:capturedSql = $Sql; $script:capturedParams.Add($Parameters); 1 }
            }
        }

        It 'upserts one software_ci per RESOLVED install and drops unresolved-device rows' {
            InModuleScope ImperionPipeline {
                $r = Invoke-ImperionSoftwareCiMerge -Confirm:$false
                $r.apps | Should -Be 3
                $r.merged | Should -Be 2
                $r.unresolved | Should -Be 1   # the Slack row has no silver device -> dropped, never written
                $r.failed | Should -Be 0
                Should -Invoke Invoke-ImperionDbNonQuery -Times 2
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Software CI merge complete' }
            }
        }

        It 'is an idempotent ON CONFLICT (source, device_id, external_ref) upsert into software_ci' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSoftwareCiMerge -Confirm:$false | Out-Null
                $script:capturedSql | Should -Match 'INSERT INTO software_ci'
                $script:capturedSql | Should -Match "'intune'"
                $script:capturedSql | Should -Match 'ON CONFLICT \(source, device_id, external_ref\) DO UPDATE SET'
            }
        }

        It 'maps the app identity columns and resolves account through the device' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSoftwareCiMerge -Confirm:$false | Out-Null
                $chrome = $script:capturedParams | Where-Object { $_.external_ref -eq 'dev1|app1' }
                $chrome.name | Should -Be 'Google Chrome'
                $chrome.publisher | Should -Be 'Google'
                $chrome.version | Should -Be '120.0'
                $chrome.platform | Should -Be 'windows'
                $chrome.install_state | Should -Be 'installed'
                $chrome.device_id | Should -Be 'dev-uuid-1'
                $chrome.account_id | Should -Be 'acc-1'   # resolved through device.account_id
            }
        }

        It 'regex-guards the bronze text collected_at -> last_seen_at (junk -> null -> COALESCE now())' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSoftwareCiMerge -Confirm:$false | Out-Null
                $script:capturedSql | Should -Match 'COALESCE\(@last_seen_at::timestamptz, now\(\)\)'
                $chrome = $script:capturedParams | Where-Object { $_.external_ref -eq 'dev1|app1' }
                $teams  = $script:capturedParams | Where-Object { $_.external_ref -eq 'dev1|app2' }
                $chrome.last_seen_at | Should -Be '2026-06-18T00:00:00Z'
                $teams.last_seen_at | Should -BeNullOrEmpty   # 'junk' fails the regex -> null
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionSoftwareCiMerge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}
