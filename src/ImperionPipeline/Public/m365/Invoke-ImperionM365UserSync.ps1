function Invoke-ImperionM365UserSync {
    <#
    .SYNOPSIS
        Collect M365 (Entra) users into the m365_contacts bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/users.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionM365UserSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'M365 users' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionM365User -TenantId $TenantId | Set-ImperionM365UserToBronze }
        else { Get-ImperionM365User | Set-ImperionM365UserToBronze }
    }
}
