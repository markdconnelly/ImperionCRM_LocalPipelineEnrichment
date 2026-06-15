function Get-ImperionEntraRoleAssignment {
    <#
    .SYNOPSIS
        Collect a tenant's Entra directory role assignments and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for tenant-hygiene privileged-access (issue #142;
        front-end schema issue #260, table entra_role_assignments). Mints a Graph token for
        the tenant (GDAP for customer tenants), pages
        /roleManagement/directory/roleAssignments — application permission
        RoleManagement.Read.Directory, read-only — with $expand=roleDefinition,principal so
        each assignment carries the human-readable role name and the principal's
        display/type without a second lookup, and flattens each to the standard flat-table
        envelope, source 'm365', external_id = the role-assignment id.

        This is the privileged-role-membership hygiene feed: who holds Global Administrator
        and other directory roles, the directory scope of each grant, and the principal type
        (user / group / servicePrincipal). A benchmark reads role_display_name +
        principal_type to flag over-broad or unexpected privileged grants.

        Booleans/collections coerce to text via the standard scalar coercion; the full
        expanded objects live losslessly in raw_payload (bronze flat columns are all-text).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionEntraRoleAssignmentToBronze.
    .EXAMPLE
        Get-ImperionEntraRoleAssignment | Set-ImperionEntraRoleAssignmentToBronze
    .EXAMPLE
        Get-ImperionEntraRoleAssignment -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    # $expand resolves the role name + principal in one page; Invoke-ImperionGraphRequest
    # follows @odata.nextLink so large tenants page transparently.
    $assignments = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$expand=roleDefinition,principal' `
        -AccessToken $token

    # Schema issue #260 flat columns (entra_role_assignments). external_id = id.
    # principal '@odata.type' (e.g. '#microsoft.graph.user') is trimmed to a bare type.
    # principal carries '@odata.type' (a dotted member name); read principal then that exact
    # member with Get-ImperionMember — Get-ImperionPropertyPath would split the dots wrongly.
    $principalType = {
        param($assignment)
        $principal = Get-ImperionMember $assignment 'principal'
        $odataType = Get-ImperionMember $principal '@odata.type'
        if ($odataType) { ($odataType -replace '^#microsoft\.graph\.', '') } else { $null }
    }
    $map = [ordered]@{
        role_definition_id   = 'roleDefinitionId'
        role_display_name    = 'roleDefinition.displayName'
        role_is_builtin      = 'roleDefinition.isBuiltIn'
        role_template_id     = 'roleDefinition.templateId'
        principal_id         = 'principalId'
        principal_display_name = 'principal.displayName'
        principal_type       = { param($a) & $principalType $a }
        principal_upn        = 'principal.userPrincipalName'
        directory_scope_id   = 'directoryScopeId'
        app_scope_id         = 'appScopeId'
    }

    $rows = @($assignments | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra directory role assignments collected.' -Data @{
        tenant = $TenantId; assignments = @($assignments).Count; rows = $rows.Count
    }
    return $rows
}
