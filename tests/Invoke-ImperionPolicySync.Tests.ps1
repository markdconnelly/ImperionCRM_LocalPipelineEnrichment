#Requires -Modules Pester
# Hermetic test for Invoke-ImperionPolicySync: Graph + DB + drift mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionPolicySync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            # Empty env + empty registry => one dormant-safe partner run (TenantId = $null), so the
            # single-tenant assertions below behave as before; the fan-out is exercised separately.
            $env:IMPERION_M365_TENANT_IDS = ''
            Mock Get-ImperionConsentedTenant { @() }
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionGraphToken { 'token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            Mock Get-ImperionPolicyDrift { @() }
        }
    }

    It 'does not throw and splits Defender vs Intune when a config policy lacks templateReference' {
        InModuleScope ImperionPipeline {
            $tables = @{}
            Mock Invoke-ImperionBronzeUpsert { $tables[$Table] = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match 'configurationPolicies') {
                    , @(
                        [pscustomobject]@{ id = 'd1'; name = 'AV'; templateReference = [pscustomobject]@{ templateFamily = 'endpointSecurityAntivirus' } },
                        [pscustomobject]@{ id = 'i1'; name = 'Catalog' }   # NO templateReference -> must not throw
                    )
                }
                else { , @() }
            }
            { Invoke-ImperionPolicySync } | Should -Not -Throw
            @($tables['defender_xdr_security_policies']).Count | Should -Be 1
            @($tables['intune_security_policies']).Count | Should -Be 1
        }
    }

    It 'reads the literal @odata.type property for device configurations' {
        InModuleScope ImperionPipeline {
            $tables = @{}
            Mock Invoke-ImperionBronzeUpsert { $tables[$Table] = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match 'deviceConfigurations') {
                    , @([pscustomobject]@{ id = 'dc1'; displayName = 'Baseline'; '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration' })
                }
                else { , @() }
            }
            Invoke-ImperionPolicySync
            $tables['device_configuration_policies'][0].odata_type | Should -Be '#microsoft.graph.windows10GeneralConfiguration'
        }
    }

    It 'fans out over every consented client tenant (ADR-0126, #379)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConsentedTenant { @('tenant-a', 'tenant-b') }
            Mock Invoke-ImperionBronzeUpsert { [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionGraphRequest { , @() }
            $script:policyTenants = [System.Collections.Generic.List[object]]::new()
            Mock Get-ImperionPolicyDrift { $script:policyTenants.Add($TenantId); @() }
            Invoke-ImperionPolicySync
            $script:policyTenants | Should -Be @('tenant-a', 'tenant-b')
        }
    }
}
