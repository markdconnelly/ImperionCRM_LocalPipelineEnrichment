function Invoke-ImperionIntuneAppSync {
    <#
    .SYNOPSIS
        Collect Intune managed-apps into the intune_managed_apps bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/intune-apps.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionIntuneAppSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'Intune managed-apps' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionIntuneManagedApp -TenantId $TenantId | Set-ImperionIntuneManagedAppToBronze }
        else { Get-ImperionIntuneManagedApp | Set-ImperionIntuneManagedAppToBronze }
    }
}
