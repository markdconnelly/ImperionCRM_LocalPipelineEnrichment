function Get-ImperionEntraRoleAssignment {
    <#
    .SYNOPSIS
        Collect a tenant's Entra directory role assignments and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for tenant-hygiene privileged-access (issue #219/#142;
        front-end migration 0136 / #260, table entra_role_assignments). Mints a Graph token for
        the tenant (client tenants via the per-client onboarding app, §3), pages
        /roleManagement/directory/roleAssignments — application permission
        RoleManagement.Read.Directory, read-only — with $expand=roleDefinition so each
        assignment carries the human-readable role name (and its isPrivileged flag), then
        hydrates each principal's display/type via a cached by-id lookup (Graph allows only one
        $expand on this endpoint, #322), and flattens each to the standard flat-table envelope,
        source 'm365', external_id = the role-assignment id.

        This is the privileged-role-membership hygiene feed: who holds Global Administrator and
        other directory roles, whether the role is privileged (is_privileged, from the expanded
        roleDefinition), the directory scope of each grant, and the principal type
        (user / group / servicePrincipal). A benchmark reads is_privileged + role_display_name +
        principal_type to flag over-broad or unexpected privileged grants. This endpoint returns
        ACTIVE assignments, so assignment_type is 'Assigned'; PIM-eligible ('Activated')
        assignments come from a separate schedule endpoint (future enhancement).

        Flat columns are EXACTLY the migration-0136 entra_role_assignments set; the full expanded
        objects (role template/built-in, principal UPN, app scope, …) live losslessly in
        raw_payload (bronze over-collects; the flat columns are the 0136 filter).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Client tenants resolve via the
        per-client onboarding app (§3).
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
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    # Graph allows only ONE $expand on /roleAssignments (#322 — two returns HTTP 400
    # "Only one property can be expanded in a single query"). Expand roleDefinition (it carries
    # displayName + isPrivileged in the page) and resolve each principal in a second, cached
    # by-id lookup. Invoke-ImperionGraphRequest follows @odata.nextLink so large tenants page.
    $assignments = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$expand=roleDefinition' `
        -AccessToken $token

    # Hydrate the principal per assignment so the existing flat map ('principal.displayName',
    # principal '@odata.type') is unchanged. A directory role is held by few distinct principals,
    # so the cache keeps this to a handful of GETs even on a large tenant. A principal that no
    # longer resolves (deleted, or not readable) leaves principal $null — the principal_* columns
    # go null, never a hard failure (the full object still lands losslessly in raw_payload).
    $principalCache = @{}
    foreach ($assignment in $assignments) {
        $principalId = Get-ImperionMember $assignment 'principalId'
        if (-not $principalId) { continue }
        if (-not $principalCache.ContainsKey($principalId)) {
            $principalCache[$principalId] =
                try {
                    @(Invoke-ImperionGraphRequest `
                            -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$principalId" `
                            -AccessToken $token)[0]
                } catch {
                    Write-ImperionLog -Level Warn -Source 'm365' `
                        -Message 'Entra role-assignment principal lookup failed; principal columns null.' `
                        -Data @{ tenant = $TenantId; principalId = $principalId }
                    $null
                }
        }
        $assignment | Add-Member -NotePropertyName 'principal' -NotePropertyValue $principalCache[$principalId] -Force
    }

    # Migration 0136 flat columns (entra_role_assignments). external_id = id.
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
        role_definition_id     = 'roleDefinitionId'
        role_display_name      = 'roleDefinition.displayName'
        is_privileged          = 'roleDefinition.isPrivileged'
        principal_id           = 'principalId'
        principal_type         = { param($a) & $principalType $a }
        principal_display_name = 'principal.displayName'
        directory_scope_id     = 'directoryScopeId'
        # /roleManagement/directory/roleAssignments returns active assignments; PIM-eligible
        # ('Activated') are a separate schedule endpoint (future enhancement).
        assignment_type        = { 'Assigned' }
    }

    $rows = @($assignments | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra directory role assignments collected.' -Data @{
        tenant = $TenantId; assignments = @($assignments).Count; rows = $rows.Count
    }
    return $rows
}
