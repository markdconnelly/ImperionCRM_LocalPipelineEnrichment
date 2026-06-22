#Requires -Modules Pester
# Hermetic tests for Set-ImperionEntraDomainToBronze: standard envelope, projected to the
# exact entra_domains column set (front-end migration 0136 / #260; local issue #219/#142).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionEntraDomainToBronze' {
    It 'projects rows to the exact entra_domains column set and change-detect upserts' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Invoke-ImperionBronzeUpsert {
                $script:captured = @{ Table = $Table; Rows = $Rows; NoChange = [bool]$NoChangeDetect }
                [pscustomobject]@{ scanned = @($Rows).Count; inserted = @($Rows).Count; updated = 0; unchanged = 0 }
            }

            $rows = @(
                [pscustomobject]@{
                    domain_name = 'imperionllc.com'; authentication_type = 'Managed'
                    is_default = 'true'; is_initial = 'false'; is_root = 'true'; is_verified = 'true'
                    is_admin_managed = 'true'; supported_services = 'Email; OfficeCommunicationsOnline'
                    password_validity_period_in_days = '2147483647'; password_notification_window_in_days = '14'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'imperionllc.com'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionEntraDomainToBronze

            $script:captured.Table    | Should -Be 'entra_domains'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'domain_name', 'is_verified', 'is_default', 'is_initial', 'authentication_type',
                    'supported_services',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            # is_root / is_admin_managed / password_* are NOT 0136 columns — dropped from the
            # flat projection (they survive in raw_payload).
            ($projected.PSObject.Properties.Name -contains 'is_root') | Should -BeFalse
            ($projected.PSObject.Properties.Name -contains 'future_extra') | Should -BeFalse
            $projected.external_id | Should -Be 'imperionllc.com'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionEntraDomainToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ domain_name = 'd.com'; external_id = 'd.com'; content_hash = 'h' }
            { $row | Set-ImperionEntraDomainToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
