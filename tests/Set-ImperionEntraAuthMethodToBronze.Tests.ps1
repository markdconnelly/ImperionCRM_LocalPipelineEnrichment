#Requires -Modules Pester
# Hermetic tests for Set-ImperionEntraAuthMethodToBronze: standard envelope, projected to
# the exact entra_auth_methods column set (front-end migration 0077, issue #140).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionEntraAuthMethodToBronze' {
    It 'projects rows to the exact 0077 entra_auth_methods column set and change-detect upserts' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
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
                    user_principal_name = 'mark@imperionllc.com'; user_display_name = 'Mark Connelly'
                    user_type = 'member'; is_admin = 'true'
                    is_mfa_capable = 'true'; is_mfa_registered = 'true'
                    methods_registered = 'microsoftAuthenticatorPush; softwareOneTimePasscode'
                    user_preferred_method_for_secondary_authentication = 'push'
                    last_updated_date_time = '2026-06-12T03:00:00Z'
                    future_extra = 'dropme'
                    tenant_id = 't1'; source = 'm365'; external_id = 'user-guid-1'
                    collected_at = 'now'; raw_payload = '{}'; content_hash = 'h1'
                }
            )
            $tally = $rows | Set-ImperionEntraAuthMethodToBronze

            $script:captured.Table    | Should -Be 'entra_auth_methods'
            $script:captured.NoChange | Should -BeFalse
            $projected = $script:captured.Rows[0]
            ($projected.PSObject.Properties.Name | Sort-Object) | Should -Be (@(
                    'user_principal_name', 'user_display_name', 'user_type', 'is_admin',
                    'is_mfa_capable', 'is_mfa_registered',
                    'is_passwordless_capable',
                    'is_sspr_capable', 'is_sspr_enabled', 'is_sspr_registered',
                    'is_system_preferred_authentication_method_enabled',
                    'system_preferred_authentication_methods',
                    'methods_registered',
                    'user_preferred_method_for_secondary_authentication',
                    'last_updated_date_time',
                    'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
                ) | Sort-Object)
            $projected.is_mfa_registered  | Should -Be 'true'
            $projected.methods_registered | Should -Be 'microsoftAuthenticatorPush; softwareOneTimePasscode'
            $projected.is_sspr_capable    | Should -BeNullOrEmpty   # missing on input -> projected as NULL
            $projected.external_id        | Should -Be 'user-guid-1'
            $tally.scanned | Should -Be 1
        }
    }

    It 'writes nothing for empty input and honours -WhatIf' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection { throw 'should not open a connection' }
            Mock Invoke-ImperionBronzeUpsert { throw 'should not upsert' }

            (@() | Set-ImperionEntraAuthMethodToBronze).scanned | Should -Be 0
            $row = [pscustomobject]@{ user_principal_name = 'u'; external_id = 'g'; content_hash = 'h' }
            { $row | Set-ImperionEntraAuthMethodToBronze -WhatIf } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
