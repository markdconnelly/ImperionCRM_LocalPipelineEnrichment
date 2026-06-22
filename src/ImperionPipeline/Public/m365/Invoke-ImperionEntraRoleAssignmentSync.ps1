function Invoke-ImperionEntraRoleAssignmentSync {
    <#
    .SYNOPSIS
        Collect directory role assignments into the entra_role_assignments bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/entra-role-assignments.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionEntraRoleAssignmentSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'Entra role-assignments' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionEntraRoleAssignment -TenantId $TenantId | Set-ImperionEntraRoleAssignmentToBronze }
        else { Get-ImperionEntraRoleAssignment | Set-ImperionEntraRoleAssignmentToBronze }
    }
}
