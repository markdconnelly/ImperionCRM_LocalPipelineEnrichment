#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionUniFiMerge: ShouldProcess gating, no-bronze no-op,
# account resolution (mapped tenant / direct account-id / unmapped skip), create-vs-COALESCE-fill,
# the never-overwrite precedence guard, the last_seen text-cast guard, one-bad-row isolation, and
# connection reuse (issue #284; the on-prem bronze->silver merge unifi_devices -> silver device,
# ADR-0026; CONSERVATIVE/ADDITIVE pending front-end schema gaps ImperionCRM #1241).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionUniFiMerge' {
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
            Invoke-ImperionUniFiMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbQuery -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    It 'no bronze rows -> clean no-op (no match/write)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 1 }
            $r = Invoke-ImperionUniFiMerge -Confirm:$false
            $r.devices | Should -Be 0
            $r.created | Should -Be 0
            $r.updated | Should -Be 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'the read resolves account via account_tenant OR a direct account.id' {
        InModuleScope ImperionPipeline {
            $script:readSql = $null
            Mock Invoke-ImperionDbQuery { $script:readSql = $Sql; @() }
            Mock Invoke-ImperionDbNonQuery { 1 }
            Invoke-ImperionUniFiMerge -Confirm:$false | Out-Null
            $script:readSql | Should -Match 'FROM unifi_devices'
            $script:readSql | Should -Match 'LEFT JOIN account_tenant'
            $script:readSql | Should -Match 'a_direct.id = NULLIF\(u.tenant_id, ''''\)::uuid'
        }
    }

    Context 'merge contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                # Three bronze rows: (1) resolved + NEW (no existing match), (2) resolved + EXISTING
                # match (COALESCE-fill), (3) UNMAPPED account (skipped).
                Mock Invoke-ImperionDbQuery -ParameterFilter { $Sql -match 'FROM unifi_devices' } {
                    @(
                        [pscustomobject]@{ external_id = 'u-new';   tenant_id = 't1';  name = 'AP-Lobby';  model = 'U6-Pro'; status = 'online';  last_seen = '2026-06-22T00:00:00Z'; account_id = 'acc-1' }
                        [pscustomobject]@{ external_id = 'u-exist'; tenant_id = 't1';  name = 'SW-Core';   model = 'USW-48'; status = 'online';  last_seen = 'junk';                 account_id = 'acc-1' }
                        [pscustomobject]@{ external_id = 'u-orph';  tenant_id = 'tX';  name = 'GW-Edge';   model = 'UXG';    status = 'online';  last_seen = '2026-06-22T00:00:00Z'; account_id = $null }
                    )
                }
                # Match lookup: SW-Core already exists (returns an id); AP-Lobby does not.
                $script:matchSql = $null
                Mock Invoke-ImperionDbQuery -ParameterFilter { $Sql -match 'FROM device' } {
                    $script:matchSql = $Sql
                    if ($Parameters.name -eq 'SW-Core') { [pscustomobject]@{ id = 'dev-existing' } } else { @() }
                }
                $script:nonQueries = [System.Collections.Generic.List[hashtable]]::new()
                $script:nonSql = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:nonSql.Add($Sql); $script:nonQueries.Add($Parameters); 1 }
            }
        }

        It 'creates the unmatched device, fills the matched one, skips the unmapped row' {
            InModuleScope ImperionPipeline {
                $r = Invoke-ImperionUniFiMerge -Confirm:$false
                $r.devices  | Should -Be 3
                $r.created  | Should -Be 1
                $r.updated  | Should -Be 1
                $r.unmapped | Should -Be 1
                $r.failed   | Should -Be 0
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'UniFi merge complete' }
            }
        }

        It 'CREATE inserts a network/Ubiquiti device; serial stays null (UniFi has none)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionUniFiMerge -Confirm:$false | Out-Null
                $insert = $script:nonSql | Where-Object { $_ -match 'INSERT INTO device' } | Select-Object -First 1
                $insert | Should -Match "'network'"
                $insert | Should -Match "'Ubiquiti'"
                $insert | Should -Not -Match 'serial_number'
            }
        }

        It 'FILL is COALESCE-only (never overwrites a non-null identity field) and advances last_seen via GREATEST' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionUniFiMerge -Confirm:$false | Out-Null
                $fill = $script:nonSql | Where-Object { $_ -match 'UPDATE device' } | Select-Object -First 1
                $fill | Should -Match 'model        = COALESCE\(model, @model\)'
                $fill | Should -Match 'status       = COALESCE\(status, @status\)'
                $fill | Should -Match 'last_seen_at = GREATEST\(last_seen_at, @last_seen_at::timestamptz\)'
            }
        }

        It 'regex-guards the bronze text last_seen (junk -> null) on the matched fill' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionUniFiMerge -Confirm:$false | Out-Null
                # The SW-Core fill carries last_seen='junk' -> last_seen_at must be null.
                $fillParams = $script:nonQueries | Where-Object { $_.ContainsKey('id') -and $_.id -eq 'dev-existing' } | Select-Object -First 1
                $fillParams.last_seen_at | Should -BeNullOrEmpty
                # The AP-Lobby insert carries a valid ISO ts -> preserved.
                $insertParams = $script:nonQueries | Where-Object { $_.ContainsKey('account_id') -and $_.name -eq 'AP-Lobby' } | Select-Object -First 1
                $insertParams.last_seen_at | Should -Be '2026-06-22T00:00:00Z'
            }
        }

        It 'matches on (account_id, lower(btrim(name))) within the owning account' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionUniFiMerge -Confirm:$false | Out-Null
                $script:matchSql | Should -Match 'FROM device'
                $script:matchSql | Should -Match 'account_id = @account_id::uuid'
                $script:matchSql | Should -Match 'lower\(btrim\(name\)\) = lower\(btrim\(@name\)\)'
            }
        }
    }

    It 'one bad row never blocks the rest (per-row try/catch)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery -ParameterFilter { $Sql -match 'FROM unifi_devices' } {
                @(
                    [pscustomobject]@{ external_id = 'u-bad';  tenant_id = 't1'; name = 'Bad';  model = 'x'; status = 'online'; last_seen = $null; account_id = 'acc-1' }
                    [pscustomobject]@{ external_id = 'u-good'; tenant_id = 't1'; name = 'Good'; model = 'y'; status = 'online'; last_seen = $null; account_id = 'acc-1' }
                )
            }
            Mock Invoke-ImperionDbQuery -ParameterFilter { $Sql -match 'FROM device' } { @() }
            Mock Invoke-ImperionDbNonQuery {
                if ($Parameters.name -eq 'Bad') { throw 'boom' }
                1
            }
            $r = Invoke-ImperionUniFiMerge -Confirm:$false
            $r.created | Should -Be 1
            $r.failed  | Should -Be 1
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Error' -and $Message -match 'UniFi merge failed for device u-bad' }
        }
    }

    It 'reuses a passed connection without disposing it' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            Mock Invoke-ImperionDbNonQuery { 1 }
            $disposed = @{ v = $false }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
            Invoke-ImperionUniFiMerge -Connection $conn -Confirm:$false | Out-Null
            Should -Invoke New-ImperionDbConnection -Times 0
            $disposed.v | Should -BeFalse
        }
    }
}
