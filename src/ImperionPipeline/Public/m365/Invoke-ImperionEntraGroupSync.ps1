function Invoke-ImperionEntraGroupSync {
    <#
    .SYNOPSIS
        Collect Entra/M365 group inventory into the m365_groups bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/entra-groups.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionEntraGroupSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'Entra group inventory' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionM365Group -TenantId $TenantId | Set-ImperionM365GroupToBronze }
        else { Get-ImperionM365Group | Set-ImperionM365GroupToBronze }
    }
}
