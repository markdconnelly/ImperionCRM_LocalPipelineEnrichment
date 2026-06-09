#Requires -Modules Pester
# Hermetic test for Invoke-ImperionSecureScoreSync: Graph + DB are mocked in module scope.
# Regression guard for StrictMode-safe scriptblock selectors (enabledServices / threats absent).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionSecureScoreSync' {
    It 'does not throw when secureScore / control-profile items omit optional fields' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionGraphToken { 'token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match 'secureScores') {
                    , @([pscustomobject]@{ id = 's1'; currentScore = 10; maxScore = 100 })           # no enabledServices
                }
                else {
                    , @([pscustomobject]@{ id = 'c1'; controlName = 'MFA'; maxScore = 10 })            # no threats
                }
            }
            { Invoke-ImperionSecureScoreSync } | Should -Not -Throw
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 2
        }
    }

    It 'flattens enabledServices / threats when present' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionGraphToken { 'token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert {
                $captured[$Table] = $Rows
                [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 }
            }
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match 'secureScores') {
                    , @([pscustomobject]@{ id = 's1'; currentScore = 10; enabledServices = @('Exchange', 'AAD') })
                }
                else {
                    , @([pscustomobject]@{ id = 'c1'; controlName = 'MFA'; threats = @('Account Breach') })
                }
            }
            Invoke-ImperionSecureScoreSync
            $captured['secure_scores'][0].enabled_services | Should -Be 'Exchange; AAD'
            $captured['secure_score_control_profiles'][0].threats | Should -Be 'Account Breach'
        }
    }
}
