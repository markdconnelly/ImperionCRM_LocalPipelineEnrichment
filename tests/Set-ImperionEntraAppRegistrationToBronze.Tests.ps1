#Requires -Modules Pester
# Hermetic tests for Set-ImperionEntraAppRegistrationToBronze: standard envelope, projected
# to the exact entra_app_registrations column set (front-end migration 0136 / #260; local #219/#142).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionEntraAppRegistrationToBronze' {
    It 'projects rows to the exact entra_app_registrations column set and change-detect upserts' {
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
                    app_id = 'client-guid-1'; display_name = 'Imperion Onboarding'
                    sign_in_audience = 'AzureADMyOrg'; publisher_domain = 'imperionllc.com'
                    created_date_time = '2025-06-01T00:00:00Z'
                    key_credential_count = '1'; password_credential_count = '2'
                    earliest_credential_expiry = '2026-07-01T00:00:00Z'; has_expired_credential = 'false'
                    verified_publisher = 'Imperion LLC'   # not a 0136 column — should be dropped
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'app-obj-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionEntraAppRegistrationToBronze

            $script:captured.Table    | Should -Be 'entra_app_registrations'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'app_id', 'display_name', 'sign_in_audience', 'publisher_domain', 'created_date_time',
                    'key_credential_count', 'password_credential_count',
                    'earliest_credential_expiry', 'has_expired_credential',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            ($projected.PSObject.Properties.Name -contains 'verified_publisher') | Should -BeFalse
            ($projected.PSObject.Properties.Name -contains 'future_extra') | Should -BeFalse
            $projected.earliest_credential_expiry | Should -Be '2026-07-01T00:00:00Z'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionEntraAppRegistrationToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ app_id = 'a'; external_id = 'app'; content_hash = 'h' }
            { $row | Set-ImperionEntraAppRegistrationToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
