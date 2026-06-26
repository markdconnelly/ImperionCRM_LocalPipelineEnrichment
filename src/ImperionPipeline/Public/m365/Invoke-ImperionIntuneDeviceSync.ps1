function Invoke-ImperionIntuneDeviceSync {
    <#
    .SYNOPSIS
        Collect Intune managedDevices device-compliance into the intune_managed_devices bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/intune-devices.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionIntuneDeviceSync
    #>
    [CmdletBinding()]
    param([string] $TenantId)

    # -TenantId pins the sweep to one tenant (the tenant-outer driver, #359); no arg => the
    # registry-driven estate fan-out (#358). Forward only when supplied so the default is unchanged.
    $sweep = @{}
    if ($PSBoundParameters.ContainsKey('TenantId')) { $sweep.TenantId = $TenantId }
    Invoke-ImperionM365EstateSweep @sweep -Label 'Intune managed-devices' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionM365Device -TenantId $TenantId | Set-ImperionIntuneManagedDeviceToBronze }
        else { Get-ImperionM365Device | Set-ImperionIntuneManagedDeviceToBronze }
    }
}
