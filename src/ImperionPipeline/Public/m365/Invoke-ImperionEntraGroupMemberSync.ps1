function Invoke-ImperionEntraGroupMemberSync {
    <#
    .SYNOPSIS
        Collect Entra/M365 group membership edges into the m365_group_members bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/entra-group-members.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionEntraGroupMemberSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'Entra group membership' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionM365GroupMember -TenantId $TenantId | Set-ImperionM365GroupMemberToBronze }
        else { Get-ImperionM365GroupMember | Set-ImperionM365GroupMemberToBronze }
    }
}
