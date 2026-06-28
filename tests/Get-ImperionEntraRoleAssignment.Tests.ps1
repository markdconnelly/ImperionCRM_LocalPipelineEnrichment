#Requires -Modules Pester
# Hermetic tests for Get-ImperionEntraRoleAssignment: Graph token + request mocked (issue #219/#142).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionEntraRoleAssignment' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            # URI-aware: the roleAssignments page expands ONLY roleDefinition (#322); each
            # principal is resolved by a separate directoryObjects/{id} GET.
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -like '*roleManagement/directory/roleAssignments*') {
                    @(
                        [pscustomobject]@{
                            id = 'assignment-1'; roleDefinitionId = 'role-ga'; principalId = 'user-mark'
                            directoryScopeId = '/'; appScopeId = $null
                            roleDefinition = [pscustomobject]@{ displayName = 'Global Administrator'; isPrivileged = $true; isBuiltIn = $true; templateId = '62e90394-69f5-4237-9190-012177145e10' }
                        }
                        [pscustomobject]@{
                            id = 'assignment-2'; roleDefinitionId = 'role-reader'; principalId = 'sp-app'
                            directoryScopeId = '/'
                            roleDefinition = [pscustomobject]@{ displayName = 'Directory Readers'; isPrivileged = $false; isBuiltIn = $true }
                        }
                    )
                } elseif ($Uri -like '*directoryObjects/user-mark*') {
                    @([pscustomobject]@{ displayName = 'Mark Connelly'; userPrincipalName = 'mark@imperionllc.com' } |
                        Add-Member -PassThru -NotePropertyName '@odata.type' -NotePropertyValue '#microsoft.graph.user')
                } elseif ($Uri -like '*directoryObjects/sp-app*') {
                    @([pscustomobject]@{ displayName = 'Imperion Pipeline App' } |
                        Add-Member -PassThru -NotePropertyName '@odata.type' -NotePropertyValue '#microsoft.graph.servicePrincipal')
                }
            }
        }
    }

    It 'flattens role assignments with expanded role + principal to the migration-0136 columns' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionEntraRoleAssignment)
            $rows.Count | Should -Be 2

            $ga = $rows | Where-Object { $_.external_id -eq 'assignment-1' }
            $ga.role_definition_id     | Should -Be 'role-ga'
            $ga.role_display_name      | Should -Be 'Global Administrator'
            $ga.is_privileged          | Should -Be 'true'          # from the expanded roleDefinition
            $ga.principal_id           | Should -Be 'user-mark'
            $ga.principal_display_name | Should -Be 'Mark Connelly'
            $ga.principal_type         | Should -Be 'user'          # @odata.type trimmed to bare type
            $ga.directory_scope_id     | Should -Be '/'
            $ga.assignment_type        | Should -Be 'Assigned'      # active assignment (this endpoint)
            # principal_upn / role_is_builtin are NOT 0136 flat columns (they live in raw_payload).
            ($ga.PSObject.Properties.Name -contains 'principal_upn') | Should -BeFalse
            $ga.source                 | Should -Be 'm365'
            $ga.tenant_id              | Should -Be 'partner'
        }
    }

    It 'resolves a service-principal principal type and a non-privileged role' {
        InModuleScope ImperionPipeline {
            $sp = @(Get-ImperionEntraRoleAssignment) | Where-Object { $_.external_id -eq 'assignment-2' }
            $sp.principal_type      | Should -Be 'servicePrincipal'
            $sp.role_display_name   | Should -Be 'Directory Readers'
            $sp.is_privileged       | Should -Be 'false'
        }
    }

    It 'requests roleAssignments with a SINGLE $expand=roleDefinition (Graph rejects two, #322)' {
        InModuleScope ImperionPipeline {
            Get-ImperionEntraRoleAssignment | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$expand=roleDefinition'
            }
        }
    }

    It 'resolves each principal via a directoryObjects by-id lookup' {
        InModuleScope ImperionPipeline {
            Get-ImperionEntraRoleAssignment | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/directoryObjects/user-mark'
            }
        }
    }

    It 'caches the principal lookup — one GET per distinct principal id' {
        InModuleScope ImperionPipeline {
            # Two assignments sharing one principal must trigger exactly one directoryObjects GET.
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -like '*roleManagement/directory/roleAssignments*') {
                    @(
                        [pscustomobject]@{ id = 'a1'; roleDefinitionId = 'r1'; principalId = 'dup'; directoryScopeId = '/'; roleDefinition = [pscustomobject]@{ displayName = 'R1'; isPrivileged = $false } }
                        [pscustomobject]@{ id = 'a2'; roleDefinitionId = 'r2'; principalId = 'dup'; directoryScopeId = '/'; roleDefinition = [pscustomobject]@{ displayName = 'R2'; isPrivileged = $false } }
                    )
                } else {
                    @([pscustomobject]@{ displayName = 'Shared' } | Add-Member -PassThru -NotePropertyName '@odata.type' -NotePropertyValue '#microsoft.graph.user')
                }
            }
            Get-ImperionEntraRoleAssignment | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter { $Uri -like '*directoryObjects/dup' }
        }
    }

    It 'does not throw when a principal cannot be resolved (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest {
                if ($Uri -like '*roleManagement/directory/roleAssignments*') {
                    @([pscustomobject]@{ id = 'bare'; roleDefinitionId = 'r'; principalId = 'p'; directoryScopeId = '/' })
                } else { throw 'principal not found' }
            }
            { Get-ImperionEntraRoleAssignment } | Should -Not -Throw
            $row = @(Get-ImperionEntraRoleAssignment)[0]
            $row.principal_type | Should -BeNullOrEmpty
        }
    }
}
