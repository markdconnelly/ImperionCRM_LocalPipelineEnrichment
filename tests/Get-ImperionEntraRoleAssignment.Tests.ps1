#Requires -Modules Pester
# Hermetic tests for Get-ImperionEntraRoleAssignment: Graph token + request mocked (issue #142).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionEntraRoleAssignment' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'assignment-1'; roleDefinitionId = 'role-ga'; principalId = 'user-mark'
                        directoryScopeId = '/'; appScopeId = $null
                        roleDefinition = [pscustomobject]@{ displayName = 'Global Administrator'; isBuiltIn = $true; templateId = '62e90394-69f5-4237-9190-012177145e10' }
                        principal = ([pscustomobject]@{ displayName = 'Mark Connelly'; userPrincipalName = 'mark@imperionllc.com' } |
                            Add-Member -PassThru -NotePropertyName '@odata.type' -NotePropertyValue '#microsoft.graph.user')
                    }
                    [pscustomobject]@{
                        id = 'assignment-2'; roleDefinitionId = 'role-reader'; principalId = 'sp-app'
                        directoryScopeId = '/'
                        roleDefinition = [pscustomobject]@{ displayName = 'Directory Readers'; isBuiltIn = $true }
                        principal = ([pscustomobject]@{ displayName = 'Imperion Pipeline App' } |
                            Add-Member -PassThru -NotePropertyName '@odata.type' -NotePropertyValue '#microsoft.graph.servicePrincipal')
                    }
                )
            }
        }
    }

    It 'flattens role assignments with expanded role + principal to the schema-260 columns' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionEntraRoleAssignment)
            $rows.Count | Should -Be 2

            $ga = $rows | Where-Object { $_.external_id -eq 'assignment-1' }
            $ga.role_definition_id     | Should -Be 'role-ga'
            $ga.role_display_name      | Should -Be 'Global Administrator'
            $ga.role_is_builtin        | Should -Be 'true'
            $ga.principal_id           | Should -Be 'user-mark'
            $ga.principal_display_name | Should -Be 'Mark Connelly'
            $ga.principal_type         | Should -Be 'user'          # @odata.type trimmed to bare type
            $ga.principal_upn          | Should -Be 'mark@imperionllc.com'
            $ga.directory_scope_id     | Should -Be '/'
            $ga.source                 | Should -Be 'm365'
            $ga.tenant_id              | Should -Be 'partner'
        }
    }

    It 'resolves a service-principal principal type' {
        InModuleScope ImperionPipeline {
            $sp = @(Get-ImperionEntraRoleAssignment) | Where-Object { $_.external_id -eq 'assignment-2' }
            $sp.principal_type      | Should -Be 'servicePrincipal'
            $sp.role_display_name   | Should -Be 'Directory Readers'
        }
    }

    It 'requests roleAssignments with $expand=roleDefinition,principal' {
        InModuleScope ImperionPipeline {
            Get-ImperionEntraRoleAssignment | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$expand=roleDefinition,principal'
            }
        }
    }

    It 'does not throw when expansion is absent (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { @([pscustomobject]@{ id = 'bare'; roleDefinitionId = 'r'; principalId = 'p' }) }
            { Get-ImperionEntraRoleAssignment } | Should -Not -Throw
            $row = @(Get-ImperionEntraRoleAssignment)[0]
            $row.principal_type | Should -BeNullOrEmpty
        }
    }
}
