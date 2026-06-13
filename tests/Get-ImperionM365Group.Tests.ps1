#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365Group: Graph token + requests mocked.
# Scope guard: the collector lists /groups only — membership edges are a separate getter.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionM365Group' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'grp-unified-1'
                        displayName = 'Operations Team'; mailNickname = 'ops'
                        mail = 'ops@imperionllc.com'; description = 'Ops staff'
                        groupTypes = @('Unified'); securityEnabled = $false; mailEnabled = $true
                        visibility = 'Private'; classification = $null; isAssignableToRole = $false
                        membershipRule = $null; membershipRuleProcessingState = $null
                        onPremisesSyncEnabled = $null
                        createdDateTime = '2024-02-01T09:00:00Z'
                        renewedDateTime = '2026-05-01T09:00:00Z'; expirationDateTime = $null
                    }
                    [pscustomobject]@{
                        id = 'grp-dynamic-2'
                        displayName = 'All Engineers'; mailNickname = 'eng'
                        groupTypes = @('DynamicMembership'); securityEnabled = $true; mailEnabled = $false
                        visibility = 'Private'; isAssignableToRole = $true
                        membershipRule = 'user.department -eq "Engineering"'
                        membershipRuleProcessingState = 'On'
                        createdDateTime = '2025-01-10T12:00:00Z'
                    }
                )
            }
        }
    }

    It 'flattens the group enumeration to the 0079 columns + standard envelope' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionM365Group)
            $rows.Count | Should -Be 2

            $ops = $rows | Where-Object { $_.external_id -eq 'grp-unified-1' }
            $ops.display_name     | Should -Be 'Operations Team'
            $ops.mail_nickname    | Should -Be 'ops'
            $ops.mail             | Should -Be 'ops@imperionllc.com'
            $ops.group_types      | Should -Match 'Unified'
            $ops.security_enabled | Should -Be 'false'
            $ops.mail_enabled     | Should -Be 'true'
            $ops.visibility       | Should -Be 'Private'
            $ops.source           | Should -Be 'm365'
            $ops.tenant_id        | Should -Be 'partner'
            $ops.content_hash     | Should -Match '^[0-9a-f]{64}$'
            $ops.raw_payload      | Should -Match 'Operations Team'
        }
    }

    It 'carries the advanced dynamic-membership columns ($select-only fields)' {
        InModuleScope ImperionPipeline {
            $dyn = @(Get-ImperionM365Group) | Where-Object { $_.external_id -eq 'grp-dynamic-2' }
            $dyn.is_assignable_to_role            | Should -Be 'true'
            $dyn.membership_rule                  | Should -Be 'user.department -eq "Engineering"'
            $dyn.membership_rule_processing_state | Should -Be 'On'
            $dyn.group_types                      | Should -Match 'DynamicMembership'
        }
    }

    It 'requests the advanced properties via $select on /groups' {
        InModuleScope ImperionPipeline {
            Get-ImperionM365Group | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -match '/v1\.0/groups\?\$select=' -and
                $Uri -match 'membershipRule' -and $Uri -match 'isAssignableToRole'
            }
        }
    }

    It 'does not throw when records omit optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { @([pscustomobject]@{ id = 'bare' }) }
            { Get-ImperionM365Group } | Should -Not -Throw
        }
    }

    It 'collects from the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionM365Group -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
