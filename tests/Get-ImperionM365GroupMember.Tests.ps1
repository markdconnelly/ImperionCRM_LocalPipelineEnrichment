#Requires -Modules Pester
# Hermetic tests for Get-ImperionM365GroupMember: Graph token + requests mocked.
# Two-level call: enumerate group ids, then expand /groups/{id}/members per group.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionM365GroupMember' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            # /groups?$select=id -> two groups; /groups/{id}/members -> members per group.
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match '/groups\?\$select=id$') {
                    @([pscustomobject]@{ id = 'grp-1' }, [pscustomobject]@{ id = 'grp-2' })
                }
                elseif ($Uri -match '/groups/grp-1/members') {
                    @(
                        [pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.user'; id = 'user-a'
                            displayName = 'Ada Byron'; userPrincipalName = 'ada@imperionllc.com'; mail = 'ada@imperionllc.com'
                        }
                        [pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.group'; id = 'grp-nested'
                            displayName = 'Nested Team'; userPrincipalName = $null; mail = $null
                        }
                    )
                }
                elseif ($Uri -match '/groups/grp-2/members') {
                    @([pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.user'; id = 'user-a'
                            displayName = 'Ada Byron'; userPrincipalName = 'ada@imperionllc.com'; mail = 'ada@imperionllc.com'
                        })
                }
                else { , @() }
            }
        }
    }

    It 'emits one edge per membership with the composite external_id' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionM365GroupMember)
            $rows.Count | Should -Be 3   # grp-1: user-a + nested; grp-2: user-a

            $edge = $rows | Where-Object { $_.external_id -eq 'grp-1/user-a' }
            $edge.group_external_id          | Should -Be 'grp-1'
            $edge.member_external_id         | Should -Be 'user-a'
            $edge.member_type                | Should -Be '#microsoft.graph.user'
            $edge.member_display_name        | Should -Be 'Ada Byron'
            $edge.member_user_principal_name | Should -Be 'ada@imperionllc.com'
            $edge.source                     | Should -Be 'm365'
            $edge.tenant_id                  | Should -Be 'partner'
            $edge.content_hash               | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'retains non-user members and distinguishes them by @odata.type' {
        InModuleScope ImperionPipeline {
            $nested = @(Get-ImperionM365GroupMember) | Where-Object { $_.external_id -eq 'grp-1/grp-nested' }
            $nested.member_type        | Should -Be '#microsoft.graph.group'
            $nested.member_external_id | Should -Be 'grp-nested'
        }
    }

    It 'keys the same member in two groups as two distinct edges (composite uniqueness)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionM365GroupMember)
            ($rows | Where-Object { $_.member_external_id -eq 'user-a' }).external_id |
                Sort-Object | Should -Be @('grp-1/user-a', 'grp-2/user-a')
        }
    }

    It 'expands members for every enumerated group' {
        InModuleScope ImperionPipeline {
            Get-ImperionM365GroupMember | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -match '/groups/grp-1/members' }
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -match '/groups/grp-2/members' }
        }
    }

    It 'does not throw when a member omits userPrincipalName/mail entirely (#337)' {
        InModuleScope ImperionPipeline {
            # Graph OMITS userPrincipalName/mail for non-user members (servicePrincipal, device) —
            # the property is absent, not null. Direct $member.userPrincipalName threw under
            # StrictMode; the safe accessor must yield null and keep the edge.
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match '/groups\?\$select=id$') { @([pscustomobject]@{ id = 'grp-1' }) }
                elseif ($Uri -match '/groups/grp-1/members') {
                    @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-1'; displayName = 'Some App' })
                }
                else { , @() }
            }
            $rows = @(Get-ImperionM365GroupMember)
            $sp = @($rows | Where-Object { $_.member_external_id -eq 'sp-1' })
            $sp.Count                         | Should -Be 1
            $sp[0].member_type                | Should -Be '#microsoft.graph.servicePrincipal'
            $sp[0].member_user_principal_name | Should -BeNullOrEmpty
            $sp[0].member_mail                | Should -BeNullOrEmpty
        }
    }

    It 'skips an id-less member (no member_external_id → would 23502) and keeps the rest (#366)' {
        InModuleScope ImperionPipeline {
            # Graph occasionally returns a member with no id (an inaccessible directory object).
            # member_external_id is NOT NULL in m365_group_members, so the edge must be dropped — not
            # emitted with a null key — while the valid sibling member still lands.
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -match '/groups\?\$select=id$') { @([pscustomobject]@{ id = 'grp-1' }) }
                elseif ($Uri -match '/groups/grp-1/members') {
                    @(
                        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = $null; displayName = 'Ghost' }
                        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = 'user-a'; displayName = 'Ada Byron' }
                    )
                }
                else { , @() }
            }
            $rows = @(Get-ImperionM365GroupMember)
            $rows.Count                  | Should -Be 1
            $rows[0].member_external_id  | Should -Be 'user-a'
            @($rows | Where-Object { [string]::IsNullOrEmpty($_.member_external_id) }).Count | Should -Be 0
        }
    }

    It 'collects from the requested tenant' {
        InModuleScope ImperionPipeline {
            Get-ImperionM365GroupMember -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
