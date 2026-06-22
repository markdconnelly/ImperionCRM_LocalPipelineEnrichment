function Invoke-ImperionM365DeviceSync {
    <#
    .SYNOPSIS
        Collect Intune managed-devices into the m365_devices bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/devices.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionM365DeviceSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'M365 devices' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionM365Device -TenantId $TenantId | Set-ImperionM365DeviceToBronze }
        else { Get-ImperionM365Device | Set-ImperionM365DeviceToBronze }
    }
}
