#Requires -Modules Pester
# Hermetic test for Invoke-ImperionPurviewComplianceSync: Graph + DB + drift mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionPurviewComplianceSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionGraphToken { 'token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            Mock Get-ImperionPolicyDrift { @() }
        }
    }

    It 'flattens compliance policies to purview_compliance_policies (source m365) and upserts' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionGraphRequest {
                , @([pscustomobject]@{ id = 'pol-1'; displayName = 'DLP - Financial'; policyType = 'dlp'; state = 'enabled'; scope = 'AllUsers'; lastModifiedDateTime = '2026-06-10T00:00:00Z' })
            }
            Invoke-ImperionPurviewComplianceSync
            $captured.Table | Should -Be 'purview_compliance_policies'
            $captured.Rows[0].policy_id        | Should -Be 'pol-1'
            $captured.Rows[0].policy_name      | Should -Be 'DLP - Financial'
            $captured.Rows[0].policy_type      | Should -Be 'dlp'
            $captured.Rows[0].state            | Should -Be 'enabled'
            $captured.Rows[0].source           | Should -Be 'm365'
            $captured.Rows[0].external_id      | Should -Be 'pol-1'
        }
    }

    It 'evaluates drift scoped to the purview-compliance family only' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionGraphRequest { , @() }
            Invoke-ImperionPurviewComplianceSync
            Should -Invoke Get-ImperionPolicyDrift -Times 1 -ParameterFilter { $PolicyType -eq 'purview-compliance' }
        }
    }

    It 'does not throw on zero policies and authenticates against the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            Mock Invoke-ImperionGraphRequest { , @() }
            { Invoke-ImperionPurviewComplianceSync -TenantId 'customer-9' } | Should -Not -Throw
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
